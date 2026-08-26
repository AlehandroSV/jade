local Quoting = require("jade.util.quoting")
local Hash = require("jade.util.hash")

local Audit = {}

-- Audit configuration per entity
local audit_config = {}

-- Table name for audit logs
local AUDIT_TABLE = "jade_audit_logs"

-- Secret key for audit integrity (should be set via environment variable)
local AUDIT_SECRET_KEY = os.getenv("JADE_AUDIT_SECRET_KEY") or "jade-default-audit-key-change-me"

-- Setup audit for an entity
function Audit.setup(entity, options)
    options = options or {}
    local ignored_fields = options.ignore or {}

    audit_config[entity._table] = {
        entity = entity,
        ignored_fields = ignored_fields,
    }

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

    -- Generate integrity hash for the audit entry
    if Hash.isCryptoAvailable() then
        entry._integrity_hash = Hash.hashAuditEntry(entry, AUDIT_SECRET_KEY)
    end

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
    -- Use driver-appropriate SQL types
    local id_type = "INTEGER PRIMARY KEY"
    local timestamp_type = "TEXT"

    -- Detect driver from class name
    local driver_name = tostring(driver)
    if driver_name:find("PostgreSQL") then
        id_type = "SERIAL PRIMARY KEY"
        timestamp_type = "TIMESTAMPTZ DEFAULT NOW()"
    elseif driver_name:find("MySQL") then
        id_type = "INTEGER PRIMARY KEY AUTO_INCREMENT"
        timestamp_type = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
    else
        -- SQLite and others
        id_type = "INTEGER PRIMARY KEY"
        timestamp_type = "TEXT"
    end

    local create_sql = string.format(
        [[CREATE TABLE IF NOT EXISTS %s (
            id %s,
            table_name VARCHAR(255) NOT NULL,
            record_id VARCHAR(255),
            action VARCHAR(50) NOT NULL,
            changes TEXT,
            created_at %s,
            _integrity_hash VARCHAR(64)
        )]],
        Quoting.quoteIdentifier(AUDIT_TABLE),
        id_type,
        timestamp_type
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

-- Verify integrity of an audit log entry
--- @param entry table Audit log entry from database
--- @param secret_key? string Optional override for the secret key
--- @return boolean true if integrity is valid (or if hashing not available)
function Audit.verifyIntegrity(entry, secret_key)
    if not entry._integrity_hash then
        -- No hash present, cannot verify (old entries before integrity feature)
        return true
    end
    
    local key = secret_key or AUDIT_SECRET_KEY
    return Hash.verifyAuditEntry(entry, key)
end

-- Verify integrity of all audit logs matching filters
--- @param driver table Database driver
--- @param filters? table Optional filters for which logs to verify
--- @return table Results: {total=number, verified=number, failed=number, failed_entries={}}
function Audit.verifyAllIntegrity(driver, filters)
    local entries = Audit.query(driver, filters or {})
    local results = {
        total = #entries,
        verified = 0,
        failed = 0,
        failed_entries = {},
    }
    
    for i, entry in ipairs(entries) do
        if Audit.verifyIntegrity(entry) then
            results.verified = results.verified + 1
        else
            results.failed = results.failed + 1
            results.failed_entries[#results.failed_entries + 1] = entry
        end
    end
    
    return results
end

-- Set a custom audit secret key (call this during application initialization)
--- @param key string Secret key for HMAC signing
function Audit.setSecretKey(key)
    AUDIT_SECRET_KEY = key
end

-- Clear audit config (for testing)
function Audit.clear()
    audit_config = {}
end

return Audit
