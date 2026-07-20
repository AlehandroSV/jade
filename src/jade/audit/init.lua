local Quoting = require("jade.util.quoting")

local Audit = {}

-- Audit configuration per entity
local audit_config = {}

-- Table name for audit logs
local AUDIT_TABLE = "jade_audit_logs"

-- Setup audit for an entity
function Audit.setup(entity, options)
    options = options or {}
    local ignored_fields = options.ignore or {}

    audit_config[entity._table] = {
        entity = entity,
        ignored_fields = ignored_fields,
    }

    local old_values = {}

    entity:beforeCreate(function(data)
        data._audit_action = "create"
    end)

    entity:beforeUpdate(function(data)
        data._audit_action = "update"
    end)

    entity:beforeDelete(function(data)
        data._audit_action = "delete"
    end)

    entity:afterCreate(function(inst, data)
        Audit._log(entity, inst, "create", nil, data)
    end)

    entity:afterUpdate(function(inst, data)
        local changes = {}
        for k, v in pairs(data) do
            if not k:match("^_audit") and inst._data[k] ~= v then
                changes[k] = { old = inst._data[k], new = v }
            end
        end
        if next(changes) then
            Audit._log(entity, inst, "update", changes, nil)
        end
    end)

    entity:afterDelete(function(inst, data)
        Audit._log(entity, inst, "delete", nil, nil)
    end)

    return true
end

-- Internal: write an audit log entry
function Audit._log(entity, instance, action, changes, raw_data)
    local config = audit_config[entity._table]
    if not config then return end

    local driver = entity._driver
    if not driver then return end

    -- Filter out ignored fields from changes
    if changes then
        local filtered = {}
        for field, change in pairs(changes) do
            local ignored = false
            for _, ig in ipairs(config.ignored_fields) do
                if ig == field then
                    ignored = true
                    break
                end
            end
            if not ignored then
                filtered[field] = change
            end
        end
        changes = next(filtered) and filtered or nil
    end

    -- Try to create audit table if it doesn't exist
    pcall(function()
        Audit._ensureTable(driver)
    end)

    local changes_json = nil
    if changes then
        local ok, encoded = pcall(require, "dkjson")
        if ok then
            changes_json = encoded.encode(changes)
        else
            -- Fallback: simple key=value encoding
            local parts = {}
            for k, v in pairs(changes) do
                parts[#parts + 1] = k .. "=" .. tostring(v.old) .. "->" .. tostring(v.new)
            end
            changes_json = table.concat(parts, ", ")
        end
    end

    local entry = {
        table_name = entity._table,
        record_id = instance and instance._data and tostring(instance._data.id) or nil,
        action = action,
        changes = changes_json,
        created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    local cols = {}
    local vals = {}
    local placeholders = {}
    for k, v in pairs(entry) do
        cols[#cols + 1] = Quoting.quoteIdentifier(k)
        vals[#vals + 1] = v
        placeholders[#placeholders + 1] = "?"
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES (%s)",
        Quoting.quoteIdentifier(AUDIT_TABLE),
        table.concat(cols, ", "),
        table.concat(placeholders, ", ")
    )

    pcall(function()
        driver:execute(sql, vals)
    end)
end

-- Ensure audit logs table exists
function Audit._ensureTable(driver)
    local create_sql = string.format(
        [[CREATE TABLE IF NOT EXISTS %s (
            id SERIAL PRIMARY KEY,
            table_name VARCHAR(255) NOT NULL,
            record_id VARCHAR(255),
            action VARCHAR(50) NOT NULL,
            changes TEXT,
            created_at TIMESTAMPTZ DEFAULT NOW()
        )]],
        Quoting.quoteIdentifier(AUDIT_TABLE)
    )
    driver:execute(create_sql)
end

-- Query audit logs
function Audit.query(driver, filters)
    filters = filters or {}
    local conditions = {}
    local bindings = {}

    if filters.table_name then
        conditions[#conditions + 1] = "table_name = ?"
        bindings[#bindings + 1] = filters.table_name
    end

    if filters.record_id then
        conditions[#conditions + 1] = "record_id = ?"
        bindings[#bindings + 1] = tostring(filters.record_id)
    end

    if filters.action then
        conditions[#conditions + 1] = "action = ?"
        bindings[#bindings + 1] = filters.action
    end

    local where = #conditions > 0 and (" WHERE " .. table.concat(conditions, " AND ")) or ""
    local sql = string.format("SELECT * FROM %s%s ORDER BY created_at DESC", Quoting.quoteIdentifier(AUDIT_TABLE), where)

    return driver:execute(sql, bindings)
end

-- Clear audit config (for testing)
function Audit.clear()
    audit_config = {}
end

return Audit
