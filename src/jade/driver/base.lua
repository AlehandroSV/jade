local Driver = {}
Driver.__index = Driver

-- Abstract methods (must be implemented by drivers)
-- connect(config)
-- disconnect()
-- execute(sql, bindings)
-- generateSelect(query) -> sql, bindings
-- generateInsert(table_name, data, entity) -> sql, bindings
-- generateUpdate(table_name, data, where) -> sql, bindings
-- generateDelete(table_name, where) -> sql, bindings
-- mapType(column_type) -> db_type_string
-- getConnection() -> connection
-- beginTransaction(conn)
-- commitTransaction(conn)
-- rollbackTransaction(conn)
-- executeWithConnection(conn, sql, bindings)
-- dropTableCascade() -> boolean (whether DROP TABLE supports CASCADE)

function Driver.new()
    return setmetatable({}, Driver)
end

function Driver:connect(config)
    error("Driver:connect() not implemented")
end

function Driver:disconnect()
    error("Driver:disconnect() not implemented")
end

function Driver:execute(sql, bindings)
    error("Driver:execute() not implemented")
end

function Driver:generateSelect(query)
    error("Driver:generateSelect() not implemented")
end

function Driver:generateInsert(table_name, data, entity)
    error("Driver:generateInsert() not implemented")
end

function Driver:generateUpdate(table_name, data, where)
    error("Driver:generateUpdate() not implemented")
end

function Driver:generateDelete(table_name, where)
    error("Driver:generateDelete() not implemented")
end

function Driver:mapType(column_type)
    error("Driver:mapType() not implemented")
end

function Driver:getConnection()
    error("Driver:getConnection() not implemented")
end

function Driver:beginTransaction(conn)
    error("Driver:beginTransaction() not implemented")
end

function Driver:commitTransaction(conn)
    error("Driver:commitTransaction() not implemented")
end

function Driver:rollbackTransaction(conn)
    error("Driver:rollbackTransaction() not implemented")
end

function Driver:executeWithConnection(conn, sql, bindings)
    error("Driver:executeWithConnection() not implemented")
end

-- Returns true if the database supports CASCADE in DROP TABLE statements.
-- Override in drivers that do not support CASCADE (e.g., SQLite).
function Driver:dropTableCascade()
    return true
end

-- Returns true if the database supports AUTO_INCREMENT syntax.
-- Override in drivers that support AUTO_INCREMENT (e.g., MySQL).
function Driver:supportsAutoIncrement()
    return false
end

-- Returns the AUTO_INCREMENT keyword for the specific database.
-- Override in drivers that use different syntax (e.g., SQLite uses AUTOINCREMENT).
function Driver:autoIncrementKeyword()
    return "AUTO_INCREMENT"
end

-- Quote an identifier for the specific database.
-- Override in drivers that use different quoting (e.g., MySQL uses backticks).
function Driver:quoteIdentifier(name)
    return '"' .. name:gsub('"', '""') .. '"'
end

return Driver