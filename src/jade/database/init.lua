local M = {}

-- Registered database connections
local connections = {}

-- Default connection name
local default_connection = nil

-- Register a named database connection
function M.register(name, config)
    connections[name] = config
end

-- Connect to a named database
function M.connect(name)
    local config = connections[name]
    if not config then
        error("Database '" .. name .. "' not registered. Use jade.database.register() first.")
    end

    local drivers = require("jade.driver")
    local driver_name = config.driver or "postgresql"
    local DriverClass = drivers.get(driver_name)
    local driver = DriverClass.new()
    driver:connect(config)

    return driver
end

-- Set the default connection name
function M.setDefault(name)
    default_connection = name
end

-- Get the default connection name
function M.getDefault()
    return default_connection
end

-- Get all registered connection names
function M.getNames()
    local names = {}
    for name in pairs(connections) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Get config for a connection
function M.getConfig(name)
    return connections[name]
end

-- Remove a connection
function M.remove(name)
    connections[name] = nil
end

-- Clear all connections (for testing)
function M.clear()
    connections = {}
    default_connection = nil
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

return M
