local Driver = require("jade.driver.base")
local pgmoon = require("pgmoon")
local Pool = require("jade.driver.pool")
local Quoting = require("jade.util.quoting")

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
    self._pool = nil
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
    if self._pool then
        self._pool:close()
        self._pool = nil
    end
    if self._conn then
        self._conn:disconnect()
        self._conn = nil
    end
end

-- Close a single connection (used by pool)
function PostgreSQL:closeConnection(conn)
    if conn then
        conn:disconnect()
    end
end

-- Transaction methods
function PostgreSQL:getConnection()
    local pg = pgmoon.new(self._config)
    local ok, err = pg:connect()
    if not ok then
        error("Failed to connect to PostgreSQL: " .. tostring(err))
    end
    return pg
end

function PostgreSQL:beginTransaction(conn)
    local res, err = conn:query("BEGIN")
    if not res then
        error("Failed to begin transaction: " .. tostring(err))
    end
end

function PostgreSQL:commitTransaction(conn)
    local res, err = conn:query("COMMIT")
    if not res then
        error("Failed to commit transaction: " .. tostring(err))
    end
end

function PostgreSQL:rollbackTransaction(conn)
    local res, err = conn:query("ROLLBACK")
    if not res then
        error("Failed to rollback transaction: " .. tostring(err))
    end
end

function PostgreSQL:executeWithConnection(conn, sql, bindings)
    if bindings and #bindings > 0 then
        local res, err = conn:query(sql, table.unpack(bindings))
        if not res then
            error("Query failed: " .. tostring(err))
        end
        return res
    else
        local res, err = conn:query(sql)
        if not res then
            error("Query failed: " .. tostring(err))
        end
        return res
    end
end

function PostgreSQL:execute(sql, bindings)
    -- Use pool if available
    if self._pool then
        return self._pool:execute(sql, bindings)
    end

    -- Otherwise use shared connection
    self:_ensureConnected()
    if bindings and #bindings > 0 then
        local res, err = self._conn:query(sql, table.unpack(bindings))
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

function PostgreSQL:dropTableCascade()
    return true
end

-- Helper to convert ? placeholders to $N for pgmoon
local function convertPlaceholders(sql, bindings, start_idx)
    local idx = start_idx or 1
    sql = sql:gsub("%?", function()
        local s = "$" .. idx
        idx = idx + 1
        return s
    end)
    return sql, idx
end

function PostgreSQL:generateSelect(query)
    local sql = {}
    local bindings = {}

    -- SELECT clause with DISTINCT
    local select_prefix = "SELECT"
    if query._distinct then
        select_prefix = "SELECT DISTINCT"
    end

    if #query._select > 0 then
        local resolved = {}
        for _, item in ipairs(query._select) do
            local part, part_bindings = Quoting.resolveSelectItem(item)
            resolved[#resolved + 1] = part
            for _, b in ipairs(part_bindings) do
                bindings[#bindings + 1] = b
            end
        end
        sql[#sql + 1] = select_prefix .. " " .. table.concat(resolved, ", ")
    else
        sql[#sql + 1] = select_prefix .. " *"
    end

    -- FROM clause
    sql[#sql + 1] = "FROM " .. Quoting.quoteIdentifier(query._table)

    -- JOIN clauses
    if #query._joins > 0 then
        for _, join in ipairs(query._joins) do
            local join_sql = join.type .. " JOIN " .. Quoting.quoteIdentifier(join.table) .. " ON "
            local on_sql, on_bindings = join.on:compile()
            for _, b in ipairs(on_bindings) do
                bindings[#bindings + 1] = b
            end
            -- Convert placeholders in ON clause
            local idx = #bindings - #on_bindings + 1
            on_sql = on_sql:gsub("%?", function()
                local s = "$" .. idx
                idx = idx + 1
                return s
            end)
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
        local where_sql = table.concat(where_parts, " AND ")
        -- Convert ? placeholders to $N for pgmoon
        where_sql = convertPlaceholders(where_sql, bindings, 1)
        sql[#sql + 1] = "WHERE " .. where_sql
    end

    -- GROUP BY clause
    if #query._groupBy > 0 then
        local group_parts = {}
        for _, col in ipairs(query._groupBy) do
            local col_name = col
            if type(col) == "table" and col._column then
                col_name = col._column
            end
            group_parts[#group_parts + 1] = Quoting.quoteIdentifier(col_name)
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
        local having_sql = table.concat(having_parts, " AND ")
        -- Convert ? placeholders to $N for pgmoon
        having_sql = convertPlaceholders(having_sql, bindings, 1)
        sql[#sql + 1] = "HAVING " .. having_sql
    end

    -- ORDER BY clause
    if #query._orderBy > 0 then
        local order_parts = {}
        for _, o in ipairs(query._orderBy) do
            order_parts[#order_parts + 1] = Quoting.quoteIdentifier(o.column) .. " " .. o.dir
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

function PostgreSQL:generateInsert(table_name, data, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        columns[#columns + 1] = Quoting.quoteIdentifier(key)
        placeholders[#placeholders + 1] = "$" .. i
        bindings[#bindings + 1] = value
        i = i + 1
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES (%s) RETURNING *",
        Quoting.quoteIdentifier(table_name),
        table.concat(columns, ", "),
        table.concat(placeholders, ", ")
    )

    return sql, bindings
end

function PostgreSQL:generateBulkInsert(table_name, rows, entity)
    if #rows == 0 then
        error("Cannot bulk insert zero rows")
    end

    local columns = {}
    local all_bindings = {}
    local value_sets = {}
    local i = 1

    -- Use the first row to determine columns
    for key, _ in pairs(rows[1]) do
        columns[#columns + 1] = Quoting.quoteIdentifier(key)
    end

    for _, row in ipairs(rows) do
        local placeholders = {}
        for _, col in ipairs(columns) do
            local key = col:gsub('"', '')
            placeholders[#placeholders + 1] = "$" .. i
            all_bindings[#all_bindings + 1] = row[key]
            i = i + 1
        end
        value_sets[#value_sets + 1] = "(" .. table.concat(placeholders, ", ") .. ")"
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES %s RETURNING *",
        Quoting.quoteIdentifier(table_name),
        table.concat(columns, ", "),
        table.concat(value_sets, ", ")
    )

    return sql, all_bindings
end

function PostgreSQL:generateBulkUpdate(table_name, data, where)
    local set_parts = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        set_parts[#set_parts + 1] = Quoting.quoteIdentifier(key) .. " = $" .. i
        bindings[#bindings + 1] = value
        i = i + 1
    end

    local where_sql, where_bindings = where:compile()
    for _, b in ipairs(where_bindings) do
        bindings[#bindings + 1] = b
    end

    local idx = i
    where_sql = where_sql:gsub("%?", function()
        local s = "$" .. idx
        idx = idx + 1
        return s
    end)

    local sql = string.format(
        "UPDATE %s SET %s WHERE %s RETURNING *",
        Quoting.quoteIdentifier(table_name),
        table.concat(set_parts, ", "),
        where_sql
    )

    return sql, bindings
end

function PostgreSQL:generateBulkDelete(table_name, where)
    local where_sql, bindings = where:compile()

    local idx = 1
    where_sql = where_sql:gsub("%?", function()
        local s = "$" .. idx
        idx = idx + 1
        return s
    end)

    local sql = string.format(
        "DELETE FROM %s WHERE %s RETURNING *",
        Quoting.quoteIdentifier(table_name),
        where_sql
    )

    return sql, bindings
end

function PostgreSQL:generateUpsert(table_name, data, conflict_columns, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        columns[#columns + 1] = Quoting.quoteIdentifier(key)
        placeholders[#placeholders + 1] = "$" .. i
        bindings[#bindings + 1] = value
        i = i + 1
    end

    local conflict_cols = {}
    for _, col in ipairs(conflict_columns) do
        conflict_cols[#conflict_cols + 1] = Quoting.quoteIdentifier(col)
    end

    local update_parts = {}
    for _, col in ipairs(columns) do
        local raw_col = col:gsub('"', '')
        local is_conflict = false
        for _, cc in ipairs(conflict_columns) do
            if raw_col == cc then
                is_conflict = true
                break
            end
        end
        if not is_conflict then
            update_parts[#update_parts + 1] = col .. " = EXCLUDED." .. col
        end
    end

    local sql
    if #update_parts > 0 then
        sql = string.format(
            "INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO UPDATE SET %s RETURNING *",
            Quoting.quoteIdentifier(table_name),
            table.concat(columns, ", "),
            table.concat(placeholders, ", "),
            table.concat(conflict_cols, ", "),
            table.concat(update_parts, ", ")
        )
    else
        sql = string.format(
            "INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (%s) DO NOTHING RETURNING *",
            Quoting.quoteIdentifier(table_name),
            table.concat(columns, ", "),
            table.concat(placeholders, ", "),
            table.concat(conflict_cols, ", ")
        )
    end

    return sql, bindings
end

function PostgreSQL:generateUpdate(table_name, data, where)
    local set_parts = {}
    local bindings = {}
    local i = 1

    for key, value in pairs(data) do
        set_parts[#set_parts + 1] = Quoting.quoteIdentifier(key) .. " = $" .. i
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
        Quoting.quoteIdentifier(table_name),
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
        Quoting.quoteIdentifier(table_name),
        where_sql
    )

    return sql, bindings
end

return PostgreSQL