--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief Multi-database support module

--- @class Jade.DatabaseModule
--- @field register fun(name: string, config: Jade.DatabaseConfig)
--- @field connect fun(name: string): Jade.Driver
--- @field setDefault fun(name: string)
--- @field getDefault fun(): string?
--- @field getNames fun(): string[]
--- @field getConfig fun(name: string): Jade.DatabaseConfig?
--- @field remove fun(name: string)
--- @field addReplica fun(primary: string, replica_config: Jade.DatabaseConfig)
--- @field useReplica fun(primary: string): Jade.Driver
local M = {}

--- @class Jade.DatabaseConfig
--- @field driver? string Driver type: "postgresql", "mysql", "sqlite", "mariadb", "openresty"
--- @field host? string Database host
--- @field port? number Database port
--- @field database string Database name
--- @field user? string Database user
--- @field password? string Database password
--- @field ssl? boolean Use SSL connection

-- Registered database connections
local connections = {}

-- Default connection name
local default_connection = nil
local replicas = {}
local replica_index = {}

--- Register a named database connection
--- @param name string Connection name
--- @param config Jade.DatabaseConfig Database configuration
function M.register(name, config)
    connections[name] = config
end

--- Connect to a named database
--- @param name string Connection name
--- @return Jade.Driver Database driver
function M.connect(name)
    local config = connections[name]
    if not config then
        local errors = require("jade.errors")
        errors.raise(errors.CONFIG_MISSING, {
            path = "jade.database.register('" .. tostring(name) .. "')",
        }, 2)
    end

    local drivers = require("jade.driver")
    local driver_name = config.driver or "postgresql"
    local DriverClass = drivers.get(driver_name)
    local driver = DriverClass.new()
    driver:connect(config)

    return driver
end

--- Set the default connection name
--- @param name string Connection name
function M.setDefault(name)
    default_connection = name
end

--- Get the default connection name
--- @return string? Default connection name
function M.getDefault()
    return default_connection
end

--- Get all registered connection names
--- @return string[] Connection names
function M.getNames()
    local names = {}
    for name in pairs(connections) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--- Get config for a connection
--- @param name string Connection name
--- @return Jade.DatabaseConfig? Database configuration
function M.getConfig(name)
    return connections[name]
end

--- Remove a connection
--- @param name string Connection name
function M.remove(name)
    connections[name] = nil
end

-- Clear all connections (for testing)
function M.clear()
    connections = {}
    default_connection = nil
    replicas = {}
    replica_index = {}
end

-- Configure multiple databases from a config table
-- Example:
-- jade.database.configure({
--     primary = { driver = "postgresql", host = "localhost", database = "mydb" },
--     analytics = { driver = "postgresql", host = "localhost", database = "analytics" },
-- })
function M.configure(databases)
    for name, config in pairs(databases) do
        M.register(name, config)
    end
    if not default_connection then
        -- Set first connection as default
        local names = M.getNames()
        if #names > 0 then
            M.setDefault(names[1])
        end
    end
end

-- Read replica support

-- Register read replicas for a primary connection
-- M.addReplicas("primary", { replica1_config, replica2_config })
function M.addReplicas(primary_name, replica_configs)
    if not replicas[primary_name] then
        replicas[primary_name] = {}
    end
    for _, config in ipairs(replica_configs) do
        replicas[primary_name][#replicas[primary_name] + 1] = config
    end
    replica_index[primary_name] = 0
end

-- Get a read replica using round-robin selection
function M.getReplica(primary_name)
    local rep_list = replicas[primary_name]
    if not rep_list or #rep_list == 0 then
        -- Fall back to primary
        return M.connect(primary_name)
    end

    replica_index[primary_name] = (replica_index[primary_name] or 0) + 1
    local idx = ((replica_index[primary_name] - 1) % #rep_list) + 1
    local config = rep_list[idx]

    local drivers = require("jade.driver")
    local driver_name = config.driver or "postgresql"
    local DriverClass = drivers.get(driver_name)
    local driver = DriverClass.new()
    driver:connect(config)
    return driver
end

-- Get all replicas for a primary
function M.getReplicas(primary_name)
    return replicas[primary_name] or {}
end

-- Run a function in a transaction on a specific database
-- jade.database.transaction("primary", function(driver)
--     User:create({ name = "John" })
-- end)
function M.transaction(name, fn)
    local driver = M.connect(name)
    driver:beginTransaction()
    local ok, err = pcall(fn, driver)
    if ok then
        driver:commitTransaction()
    else
        driver:rollbackTransaction()
        error(err)
    end
    return ok
end

-- Execute a query on a specific database
-- jade.database.execute("analytics", "SELECT * FROM logs")
function M.execute(name, sql, bindings)
    local driver = M.connect(name)
    return driver:execute(sql, bindings)
end

-- Check health of all registered connections
function M.healthCheck()
    local results = {}
    for name in pairs(connections) do
        local ok, driver = pcall(M.connect, name)
        if ok then
            pcall(function() driver:disconnect() end)
            results[name] = { status = "healthy" }
        else
            results[name] = { status = "unhealthy", error = tostring(driver) }
        end
    end
    return results
end

return M
