local Driver = require("jade.driver.base")
local Pool = require("jade.driver.pool")

local SQLite = {}
SQLite.__index = SQLite

setmetatable(SQLite, {
    __index = Driver,
})

function SQLite.new()
    local self = Driver.new()
    setmetatable(self, SQLite)
    self._conn = nil
    self._config = nil
    self._pool = nil
    self._env = nil
    return self
end

function SQLite:connect(config)
    self._config = {
        database = config.database or ":memory:"
    }

    -- Initialize luasql environment
    if not self._env then
        local sqlite3 = require("luasql.sqlite3")
        self._env = sqlite3.sqlite3()
    end

    -- Initialize connection pool if pool_size is specified
    if config.pool_size then
        self._pool = Pool.new(self, {
            max_size = config.pool_size or 10,
            min_size = config.pool_min or 2,
            idle_timeout = config.pool_timeout or 300,
        })
    end

    return self
end

function SQLite:_ensureConnected()
    if self._conn then return end

    -- Initialize luasql environment if not already done
    if not self._env then
        local sqlite3 = require("luasql.sqlite3")
        self._env = sqlite3.sqlite3()
    end

    local conn, err = self._env:connect(self._config.database)
    if not conn then
        error("Failed to connect to SQLite: " .. tostring(err))
    end

    -- Enable WAL mode for better concurrency
    conn:execute("PRAGMA journal_mode=WAL")
    -- Enable foreign keys
    conn:execute("PRAGMA foreign_keys=ON")

    self._conn = conn
end

function SQLite:disconnect()
    if self._pool then
        self._pool:close()
        self._pool = nil
    end
    if self._conn then
        self._conn:close()
        self._conn = nil
    end
    if self._env then
        self._env:close()
        self._env = nil
    end
end

-- Close a single connection (used by pool)
function SQLite:closeConnection(conn)
    if conn then
        conn:close()
    end
end

-- Quote identifier with backticks for SQLite
function SQLite:quoteIdentifier(name)
    return "`" .. name:gsub("`", "``") .. "`"
end

-- Transaction methods
function SQLite:getConnection()
    local conn, err = self._env:connect(self._config.database)
    if not conn then
        error("Failed to connect to SQLite: " .. tostring(err))
    end
    return conn
end

function SQLite:beginTransaction(conn)
    local res, err = conn:execute("BEGIN")
    if not res then
        error("Failed to begin transaction: " .. tostring(err))
    end
end

function SQLite:commitTransaction(conn)
    local res, err = conn:execute("COMMIT")
    if not res then
        error("Failed to commit transaction: " .. tostring(err))
    end
end

function SQLite:rollbackTransaction(conn)
    local res, err = conn:execute("ROLLBACK")
    if not res then
        error("Failed to rollback transaction: " .. tostring(err))
    end
end

-- Helper to convert ? placeholders to :n style for luasql
local function convertPlaceholders(sql, bindings)
    if not bindings or #bindings == 0 then
        return sql, nil
    end
    local params = {}
    local idx = 1
    sql = sql:gsub("%?", function()
        local name = "p" .. idx
        params[name] = bindings[idx]
        idx = idx + 1
        return ":" .. name
    end)
    return sql, params
end

function SQLite:executeWithConnection(conn, sql, bindings)
    local converted_sql, params = convertPlaceholders(sql, bindings)
    local res, err
    if params then
        res, err = conn:execute(converted_sql, params)
    else
        res, err = conn:execute(converted_sql)
    end
    if res == nil then
        error("Query failed: " .. tostring(err))
    end
    return res
end

function SQLite:execute(sql, bindings)
    -- Use pool if available
    if self._pool then
        return self._pool:execute(sql, bindings)
    end

    -- Otherwise use shared connection
    self:_ensureConnected()
    local converted_sql, params = convertPlaceholders(sql, bindings)
    local res, err
    if params then
        res, err = self._conn:execute(converted_sql, params)
    else
        res, err = self._conn:execute(converted_sql)
    end
    if res == nil then
        error("Query failed: " .. tostring(err))
    end
    return res
end

function SQLite:mapType(column_type)
    local map = {
        string = "TEXT",
        text = "TEXT",
        integer = "INTEGER",
        bigint = "INTEGER",
        float = "REAL",
        real = "REAL",
        decimal = "REAL",
        boolean = "INTEGER",
        timestamp = "TEXT",
        date = "TEXT",
        uuid = "TEXT",
        json = "TEXT",
        blob = "BLOB",
    }
    return map[column_type.type] or "TEXT"
end

function SQLite:dropTableCascade()
    return false
end

function SQLite:supportsAutoIncrement()
    return true
end

function SQLite:autoIncrementKeyword()
    return "AUTOINCREMENT"
end

function SQLite:generateSelect(query)
    local sql = {}
    local bindings = {}

    -- SELECT clause with DISTINCT
    local select_prefix = "SELECT"
    if query._distinct then
        select_prefix = "SELECT DISTINCT"
    end

    if #query._select > 0 then
        sql[#sql + 1] = select_prefix .. " " .. table.concat(query._select, ", ")
    else
        sql[#sql + 1] = select_prefix .. " *"
    end

    -- FROM clause
    sql[#sql + 1] = "FROM " .. self:quoteIdentifier(query._table)

    -- JOIN clauses
    if #query._joins > 0 then
        for _, join in ipairs(query._joins) do
            local join_sql = join.type .. " JOIN " .. self:quoteIdentifier(join.table) .. " ON "
            local on_sql, on_bindings = join.on:compile()
            for _, b in ipairs(on_bindings) do
                bindings[#bindings + 1] = b
            end
            sql[#sql + 1] = join_sql .. on_sql
        end
    end

    -- WHERE clause
    if #query._where > 0 then
        local where_parts = {}
        for _, cond in ipairs(query._where) do
            local sql_part, bind = cond:compile()
            where_parts[#where_parts + 1] = sql_part
            for _, b in ipairs(bind) do
                bindings[#bindings + 1] = b
            end
        end
        sql[#sql + 1] = "WHERE " .. table.concat(where_parts, " AND ")
    end

    -- GROUP BY clause
    if #query._groupBy > 0 then
        local group_parts = {}
        for _, col in ipairs(query._groupBy) do
            local col_name = col
            if type(col) == "table" and col._column then
                col_name = col._column
            end
            group_parts[#group_parts + 1] = self:quoteIdentifier(col_name)
        end
        sql[#sql + 1] = "GROUP BY " .. table.concat(group_parts, ", ")
    end

    -- HAVING clause
    if #query._having > 0 then
        local having_parts = {}
        for _, cond in ipairs(query._having) do
            local sql_part, bind = cond:compile()
            having_parts[#having_parts + 1] = sql_part
            for _, b in ipairs(bind) do
                bindings[#bindings + 1] = b
            end
        end
        sql[#sql + 1] = "HAVING " .. table.concat(having_parts, " AND ")
    end

    -- ORDER BY clause
    if #query._orderBy > 0 then
        local order_parts = {}
        for _, o in ipairs(query._orderBy) do
            order_parts[#order_parts + 1] = self:quoteIdentifier(o.column) .. " " .. o.dir
        end
        sql[#sql + 1] = "ORDER BY " .. table.concat(order_parts, ", ")
    end

    -- LIMIT clause
    if query._limit then
        sql[#sql + 1] = "LIMIT " .. tostring(query._limit)
    end

    -- OFFSET clause
    if query._offset then
        sql[#sql + 1] = "OFFSET " .. tostring(query._offset)
    end

    return table.concat(sql, " "), bindings
end

function SQLite:generateInsert(table_name, data, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}

    for key, value in pairs(data) do
        columns[#columns + 1] = self:quoteIdentifier(key)
        placeholders[#placeholders + 1] = "?"
        bindings[#bindings + 1] = value
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES (%s)",
        self:quoteIdentifier(table_name),
        table.concat(columns, ", "),
        table.concat(placeholders, ", ")
    )

    return sql, bindings
end

function SQLite:generateUpdate(table_name, data, where)
    local set_parts = {}
    local bindings = {}

    for key, value in pairs(data) do
        set_parts[#set_parts + 1] = self:quoteIdentifier(key) .. " = ?"
        bindings[#bindings + 1] = value
    end

    local where_sql, where_bindings = where:compile()
    for _, b in ipairs(where_bindings) do
        bindings[#bindings + 1] = b
    end

    local sql = string.format(
        "UPDATE %s SET %s WHERE %s",
        self:quoteIdentifier(table_name),
        table.concat(set_parts, ", "),
        where_sql
    )

    return sql, bindings
end

function SQLite:generateDelete(table_name, where)
    local where_sql, bindings = where:compile()

    local sql = string.format(
        "DELETE FROM %s WHERE %s",
        self:quoteIdentifier(table_name),
        where_sql
    )

    return sql, bindings
end

function SQLite:getLastInsertId()
    self:_ensureConnected()
    local res, err = self._conn:execute("SELECT last_insert_rowid() as id")
    if not res then
        error("Failed to get last insert id: " .. tostring(err))
    end
    local row = res:fetch({}, "a")
    return row and row.id
end

return SQLite
