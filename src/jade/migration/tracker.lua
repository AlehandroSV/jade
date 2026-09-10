local sanitizer = require("jade.security.sanitizer")

local M = {}

local TABLE_NAME = "_jade_migrations"

--- Normalize driver results into an array of row tables.
--- luasql drivers return a cursor userdata; pgmoon and mocks return tables.
--- Always closes luasql cursors so disconnect() does not fail.
local function fetchRows(result)
    if result == nil then
        return {}
    end

    if type(result) == "userdata" and result.fetch then
        local rows = {}
        local buf = {}
        local row = result:fetch(buf, "a")
        while row do
            -- Some luasql builds return the first column as a bare value.
            if type(row) == "string" or type(row) == "number" then
                rows[#rows + 1] = { name = row }
            else
                local copy = {}
                for k, v in pairs(buf) do
                    copy[k] = v
                end
                if copy.name == nil and copy[1] ~= nil then
                    copy.name = copy[1]
                end
                rows[#rows + 1] = copy
            end
            for k in pairs(buf) do
                buf[k] = nil
            end
            row = result:fetch(buf, "a")
        end
        if result.close then
            pcall(function() result:close() end)
        end
        return rows
    end

    if type(result) == "table" then
        return result
    end

    return {}
end

local function quoteIdentifier(driver, name)
    if driver.quoteIdentifier then
        return driver:quoteIdentifier(name)
    end
    return '"' .. name:gsub('"', '""') .. '"'
end

local function columnDef(driver, name, column)
    local sql = quoteIdentifier(driver, name) .. " " .. driver:mapType(column)
    if column._primary_key then
        sql = sql .. " PRIMARY KEY"
        if column._auto_increment and driver:supportsAutoIncrement() then
            sql = sql .. " " .. driver:autoIncrementKeyword()
        end
    else
        if not column._nullable then
            sql = sql .. " NOT NULL"
        end
        if column._unique then
            sql = sql .. " UNIQUE"
        end
        if column._default then
            sql = sql .. " DEFAULT " .. tostring(column._default)
        end
    end
    return sql
end

local function buildTrackerColumns()
    local Column = require("jade.schema.column")

    local id = Column.new(nil, "integer")
    id._primary_key = true
    id._auto_increment = true
    id._nullable = false

    local name = Column.new(nil, "string", 255)
    name._nullable = false
    name._unique = true

    local jade_version = Column.new(nil, "string", 20)

    local applied_at = Column.new(nil, "timestamp")
    applied_at._default = "CURRENT_TIMESTAMP"

    return {
        { name = "id", column = id },
        { name = "name", column = name },
        { name = "jade_version", column = jade_version },
        { name = "applied_at", column = applied_at },
    }
end

function M.createTrackerTable(driver)
    local parts = {}
    for _, def in ipairs(buildTrackerColumns()) do
        parts[#parts + 1] = "    " .. columnDef(driver, def.name, def.column)
    end

    local sql = string.format(
        "CREATE TABLE IF NOT EXISTS %s (\n%s\n)",
        quoteIdentifier(driver, TABLE_NAME),
        table.concat(parts, ",\n")
    )
    driver:execute(sql)

    -- Upgrade path for tracker tables created before jade_version existed.
    -- Portable probe: SELECT the column; missing column raises on every driver.
    local ok = pcall(function()
        local res = driver:execute("SELECT jade_version FROM " .. TABLE_NAME .. " LIMIT 1")
        fetchRows(res)
    end)
    if not ok then
        local Column = require("jade.schema.column")
        local col = Column.new(nil, "string", 20)
        local type_sql = driver:mapType(col)
        driver:execute(
            "ALTER TABLE " .. quoteIdentifier(driver, TABLE_NAME) .. " ADD COLUMN jade_version " .. type_sql
        )
    end
end

function M.getAppliedMigrations(driver)
    local sql = "SELECT name FROM " .. TABLE_NAME .. " ORDER BY id"
    local result = driver:execute(sql)
    local applied = {}
    for _, row in ipairs(fetchRows(result)) do
        applied[row.name] = true
    end
    return applied
end

function M.recordMigration(driver, name)
    -- Get Jade version without requiring jade (avoids circular dependency)
    local version = "unknown"
    local ok, versionModule = pcall(require, "jade._VERSION")
    if ok and versionModule then
        version = versionModule
    end
    -- Inline escaped values: some luasql+SQLite builds silently bind NULL.
    local sql = "INSERT INTO " .. TABLE_NAME .. " (name, jade_version) VALUES ("
        .. sanitizer.escapeString(name) .. ", "
        .. sanitizer.escapeString(version) .. ")"
    return driver:execute(sql)
end

function M.removeMigration(driver, name)
    local sql = "DELETE FROM " .. TABLE_NAME .. " WHERE name = " .. sanitizer.escapeString(name)
    return driver:execute(sql)
end

function M.getLastApplied(driver, count)
    count = count or 1
    local sql = "SELECT name FROM " .. TABLE_NAME .. " ORDER BY id DESC LIMIT " .. tostring(count)
    local result = driver:execute(sql)
    local names = {}
    for _, row in ipairs(fetchRows(result)) do
        names[#names + 1] = row.name
    end
    return names
end

return M
