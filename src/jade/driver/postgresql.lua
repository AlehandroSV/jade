local Driver = require("jade.driver.base")
local pgmoon = require("pgmoon")

local PostgreSQL = {}
PostgreSQL.__index = PostgreSQL

setmetatable(PostgreSQL, {
    __index = Driver,
})

function PostgreSQL.new()
    local self = Driver.new()
    setmetatable(self, PostgreSQL)
    self._conn = nil
    self._config = nil
    return self
end

function PostgreSQL:connect(config)
    self._config = {
        host = config.host or "localhost",
        port = config.port or 5432,
        database = config.database,
        user = config.user or "postgres",
        password = config.password or ""
    }
    return self
end

function PostgreSQL:_ensureConnected()
    if self._conn then return end
    local pg = pgmoon.new(self._config)
    local ok, err = pg:connect()
    if not ok then
        error("Failed to connect to PostgreSQL: " .. tostring(err))
    end
    self._conn = pg
end

function PostgreSQL:disconnect()
    if self._conn then
        self._conn:disconnect()
        self._conn = nil
    end
end

function PostgreSQL:execute(sql, bindings)
    self:_ensureConnected()
    if bindings and #bindings > 0 then
        local res, err = self._conn:query(sql, bindings)
        if not res then
            error("Query failed: " .. tostring(err))
        end
        return res
    else
        local res, err = self._conn:query(sql)
        if not res then
            error("Query failed: " .. tostring(err))
        end
        return res
    end
end

function PostgreSQL:mapType(column_type)
    local map = {
        string = "VARCHAR(" .. (column_type.length or 255) .. ")",
        text = "TEXT",
        integer = "INTEGER",
        bigint = "BIGSERIAL",
        float = "DOUBLE PRECISION",
        decimal = "NUMERIC(" .. (column_type.precision or 10) .. "," .. (column_type.scale or 2) .. ")",
        boolean = "BOOLEAN",
        timestamp = "TIMESTAMPTZ",
        date = "DATE",
        uuid = "UUID",
        json = "JSONB",
    }
    return map[column_type.type] or "TEXT"
end

function PostgreSQL:generateSelect(query)
    local sql = {}
    local bindings = {}

    if #query._select > 0 then
        sql[#sql + 1] = "SELECT " .. table.concat(query._select, ", ")
    else
        sql[#sql + 1] = "SELECT *"
    end

    sql[#sql + 1] = "FROM " .. query._table

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

    if #query._orderBy > 0 then
        local order_parts = {}
        for _, o in ipairs(query._orderBy) do
            order_parts[#order_parts + 1] = o.column .. " " .. o.dir
        end
        sql[#sql + 1] = "ORDER BY " .. table.concat(order_parts, ", ")
    end

    if query._limit then
        sql[#sql + 1] = "LIMIT " .. tostring(query._limit)
    end
    if query._offset then
        sql[#sql + 1] = "OFFSET " .. tostring(query._offset)
    end

    return table.concat(sql, " "), bindings
end

function PostgreSQL:generateInsert(table_name, data, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        columns[#columns + 1] = key
        placeholders[#placeholders + 1] = "$" .. i
        bindings[#bindings + 1] = value
        i = i + 1
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES (%s) RETURNING *",
        table_name,
        table.concat(columns, ", "),
        table.concat(placeholders, ", ")
    )

    return sql, bindings
end

function PostgreSQL:generateUpdate(table_name, data, where)
    local set_parts = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        set_parts[#set_parts + 1] = key .. " = $" .. i
        bindings[#bindings + 1] = value
        i = i + 1
    end

    local where_sql, where_bindings = where:compile()
    for _, b in ipairs(where_bindings) do
        bindings[#bindings + 1] = b
    end

    -- Replace ? with $N in where clause
    local idx = i
    where_sql = where_sql:gsub("%?", function()
        local s = "$" .. idx
        idx = idx + 1
        return s
    end)

    local sql = string.format(
        "UPDATE %s SET %s WHERE %s RETURNING *",
        table_name,
        table.concat(set_parts, ", "),
        where_sql
    )

    return sql, bindings
end

function PostgreSQL:generateDelete(table_name, where)
    local where_sql, bindings = where:compile()

    local idx = 1
    where_sql = where_sql:gsub("%?", function()
        local s = "$" .. idx
        idx = idx + 1
        return s
    end)

    local sql = string.format(
        "DELETE FROM %s WHERE %s RETURNING *",
        table_name,
        where_sql
    )

    return sql, bindings
end

return PostgreSQL
