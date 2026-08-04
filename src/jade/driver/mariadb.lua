local MySQL = require("jade.driver.mysql")
local log = require("jade.util.log")

local MariaDB = {}
MariaDB.__index = MariaDB
MariaDB._driver_type = "mariadb"

setmetatable(MariaDB, {
    __index = MySQL,
})

function MariaDB.new()
    local self = MySQL.new()
    setmetatable(self, MariaDB)
    self._mariadb_version = nil
    self._supports_returning = false
    self._version_detection_failed = false
    return self
end

function MariaDB:connect(config)
    MySQL.connect(self, config)
    self:_detectVersion()
    return self
end

-- Detects MariaDB version and enables RETURNING if >= 10.5.
-- On failure, sets _version_detection_failed = true and disables RETURNING silently.
function MariaDB:_detectVersion()
    self:_ensureConnected()
    local res, err = self._conn:execute("SELECT VERSION() as version")
    if not res then
        self._version_detection_failed = true
        log.warn("[MariaDB] Version detection failed: " .. tostring(err) .. ". RETURNING support disabled.")
        return
    end
    local row = res:fetch({}, "a")
    if row and row.version then
        self._mariadb_version = row.version
        local major, minor = row.version:match("(%d+)%.(%d+)")
        if major and minor then
            self._supports_returning = (tonumber(major) > 10) or
                (tonumber(major) == 10 and tonumber(minor) >= 5)
        end
    end
end

function MariaDB:generateInsert(table_name, data, entity)
    local sql, bindings = MySQL.generateInsert(self, table_name, data, entity)
    if self._supports_returning then
        sql = sql .. " RETURNING *"
    end
    return sql, bindings
end

function MariaDB:generateUpdate(table_name, data, where)
    local sql, bindings = MySQL.generateUpdate(self, table_name, data, where)
    if self._supports_returning then
        sql = sql .. " RETURNING *"
    end
    return sql, bindings
end

function MariaDB:generateDelete(table_name, where)
    local sql, bindings = MySQL.generateDelete(self, table_name, where)
    if self._supports_returning then
        sql = sql .. " RETURNING *"
    end
    return sql, bindings
end

function MariaDB:generateUpsert(table_name, data, conflict_columns, entity)
    local sql, bindings = MySQL.generateUpsert(self, table_name, data, conflict_columns, entity)
    if self._supports_returning and not sql:find("INSERT IGNORE") then
        sql = sql .. " RETURNING *"
    end
    return sql, bindings
end

function MariaDB:generateBulkInsert(table_name, rows, entity)
    local sql, bindings = MySQL.generateBulkInsert(self, table_name, rows, entity)
    if self._supports_returning then
        sql = sql .. " RETURNING *"
    end
    return sql, bindings
end

function MariaDB:mapType(column_type)
    local mariadb_overrides = {
        json = "JSON",
        uuid = "UUID",
        inet4 = "INET4",
        inet6 = "INET6",
    }
    return mariadb_overrides[column_type.type] or MySQL.mapType(self, column_type)
end

function MariaDB:supportsReturning()
    return self._supports_returning
end

function MariaDB:versionDetectionFailed()
    return self._version_detection_failed
end

return MariaDB
