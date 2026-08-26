local Driver = require("jade.driver.base")
local Pool = require("jade.driver.pool")
local Quoting = require("jade.util.quoting")
local Json = require("jade.query.json")

local MySQL = {}
MySQL.__index = MySQL
MySQL._driver_type = "mysql"

setmetatable(MySQL, {
    __index = Driver,
})

function MySQL.new()
    local self = Driver.new()
    setmetatable(self, MySQL)
    self._conn = nil
    self._config = nil
    self._pool = nil
    self._env = nil
    return self
end

function MySQL:connect(config)
    self._config = {
        host = config.host or "localhost",
        port = config.port or 3306,
        database = config.database,
        user = config.user or "root",
        password = config.password or "",
        ssl = config.ssl or false,
        ssl_verify = config.ssl_verify,
        ssl_ca = config.ssl_ca,
        ssl_cert = config.ssl_cert,
        ssl_key = config.ssl_key,
    }

    -- Initialize luasql environment
    if not self._env then
        local mysql = require("luasql.mysql")
        self._env = mysql.mysql()
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

-- Cross-platform setenv implementation
-- Uses FFI in LuaJIT, falls back to os.execute in standard Lua
local function validateEnvName(name)
    -- Environment variable names must be alphanumeric and underscores only
    -- This prevents command injection through malicious environment variable names
    if type(name) ~= "string" or name == "" then
        error("Invalid environment variable name: rejected by security policy")
    end
    if not name:match("^[A-Z_][A-Z0-9_]*$") then
        error("Invalid environment variable name: rejected by security policy")
    end
    return true
end

local function setenv(name, value)
    -- Validate environment variable name to prevent command injection
    validateEnvName(name)
    
    local ok, ffi = pcall(require, "ffi")
    if ok and ffi then
        -- LuaJIT FFI path
        ffi.cdef[[
            int setenv(const char *name, const char *value, int overwrite);
            int unsetenv(const char *name);
        ]]
        if value and value ~= "" then
            ffi.C.setenv(name, value, 1)
        else
            ffi.C.unsetenv(name)
        end
    else
        -- Standard Lua: use os.execute (affects subprocess only, but
        -- MySQL C API may read /proc/self/environ on Linux)
        -- Sanitize value to prevent shell injection
        if value and value ~= "" then
            -- Escape single quotes by replacing ' with '\''
            local safe_value = tostring(value):gsub("'", "'\\''")
            os.execute(string.format("export %s='%s'", name, safe_value))
        else
            os.execute(string.format("unset %s", name))
        end
    end
end

-- Set SSL environment variables for MySQL C API
-- The MySQL client library reads these automatically before connecting
function MySQL:_setSSLEnv()
    if not self._config.ssl then return {} end

    local saved = {}
    local ssl_vars = {
        { env = "MYSQL_OPT_SSL_MODE", value = "REQUIRED" },
        { env = "MYSQL_SSL_CA", value = self._config.ssl_ca },
        { env = "MYSQL_SSL_CERT", value = self._config.ssl_cert },
        { env = "MYSQL_SSL_KEY", value = self._config.ssl_key },
    }

    if self._config.ssl_verify == false then
        ssl_vars[1].value = "VERIFY_CA"
    elseif self._config.ssl_verify then
        ssl_vars[1].value = "VERIFY_IDENTITY"
    end

    for _, var in ipairs(ssl_vars) do
        if var.value then
            saved[var.env] = os.getenv(var.env)
            setenv(var.env, tostring(var.value))
        end
    end

    return saved
end

-- Restore saved SSL environment variables
function MySQL:_restoreSSLEnv(saved)
    for name, value in pairs(saved) do
        setenv(name, value or "")
    end
end

function MySQL:_ensureConnected()
    if self._conn then return end

    -- Initialize luasql environment if not already done
    if not self._env then
        local mysql = require("luasql.mysql")
        self._env = mysql.mysql()
    end

    local Retry = require("jade.util.retry")
    local retry_config = Retry.getConfig(self._config)

    -- Save/restore SSL env vars ONCE across all retry attempts (not per-attempt)
    -- to avoid thrashing global MYSQL_* environment variables between retries.
    local saved_env = self:_setSSLEnv()

    local function connect()
        local success, result = pcall(function()
            return self._env:connect(
                self._config.database,
                self._config.user,
                self._config.password,
                self._config.host,
                self._config.port
            )
        end)
        -- Restore SSL env vars on any exit (success or error) within this attempt
        self:_restoreSSLEnv(saved_env)

        if not success then
            error("Failed to connect to MySQL: " .. tostring(result))
        end
        local conn = result
        if not conn then
            error("Failed to connect to MySQL: nil returned")
        end
        return conn
    end

    local conn = Retry.execute(connect, retry_config, "MySQL connection")
    -- Final restore ensures clean state even if Retry.execute propagates an error
    self:_restoreSSLEnv(saved_env)
    self._conn = conn
    self:setEncryptionKey()
end

function MySQL:disconnect()
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
function MySQL:closeConnection(conn)
    if conn then
        conn:close()
    end
end

-- Quote identifier with backticks for MySQL
function MySQL:quoteIdentifier(name)
    return "`" .. name:gsub("`", "``") .. "`"
end

-- Set encryption key as session variable on connection
-- NOTE: Uses global config for connection-level key. Per-entity configs require
-- separate DB connections in AES/native mode (one key per connection session).
-- Custom encryption bypasses this limitation (Lua-level decryption).
function MySQL:setEncryptionKey(conn)
    conn = conn or self._conn
    local Encryption = require("jade.encryption")
    if Encryption.isEnabled() then
        local key = Encryption.getKey()
        -- Escape backslashes first, then single quotes for MySQL
        local escaped_key = key:gsub("\\", "\\\\"):gsub("'", "''")
        local sql = "SET @jade_encryption_key = '" .. escaped_key .. "'"
        local res, err = conn:execute(sql)
        if not res then
            error("Failed to set encryption key session variable: " .. tostring(err))
        end
    end
end

-- Transaction methods
function MySQL:getConnection()
    -- Set SSL env vars, connect, then restore (wrapped in pcall for safety)
    local saved_env = self:_setSSLEnv()
    local success, result = pcall(function()
        return self._env:connect(
            self._config.database,
            self._config.user,
            self._config.password,
            self._config.host,
            self._config.port
        )
    end)
    self:_restoreSSLEnv(saved_env)

    if not success then
        error("Failed to connect to MySQL: " .. tostring(result))
    end
    local conn = result
    if not conn then
        error("Failed to connect to MySQL: nil returned")
    end
    -- Set encryption key for new connection
    self:setEncryptionKey(conn)
    return conn
end

function MySQL:beginTransaction(conn)
    local res, err = conn:execute("START TRANSACTION")
    if not res then
        error("Failed to begin transaction: " .. tostring(err))
    end
end

function MySQL:commitTransaction(conn)
    local res, err = conn:execute("COMMIT")
    if not res then
        error("Failed to commit transaction: " .. tostring(err))
    end
end

function MySQL:rollbackTransaction(conn)
    local res, err = conn:execute("ROLLBACK")
    if not res then
        error("Failed to rollback transaction: " .. tostring(err))
    end
end

-- Set query timeout (MySQL uses max_execution_time in milliseconds)
function MySQL:setQueryTimeout(timeout_ms)
    self:_ensureConnected()
    local sql = "SET max_execution_time = " .. tostring(timeout_ms)
    local res, err = self._conn:execute(sql)
    if not res then
        error("Failed to set query timeout: " .. tostring(err))
    end
end

-- Clear query timeout
function MySQL:clearQueryTimeout()
    self:_ensureConnected()
    local sql = "SET max_execution_time = 0"
    local res, err = self._conn:execute(sql)
    if not res then
        error("Failed to clear query timeout: " .. tostring(err))
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

function MySQL:executeWithConnection(conn, sql, bindings)
    local converted_sql, params = convertPlaceholders(sql, bindings)
    local res, err
    if params then
        res, err = conn:execute(converted_sql, params)
    else
        res, err = conn:execute(converted_sql)
    end
    if not res then
        error("Query failed: " .. tostring(err))
    end
    return res
end

function MySQL:execute(sql, bindings)
    -- Use pool if available
    if self._pool then
        return self._pool:execute(sql, bindings)
    end

    -- Apply rate limiting if enabled (use connection ID or table name as key)
    local RateLimit = require("jade.security.ratelimit")
    if RateLimit.isEnabled() then
        local key = self._conn and tostring(self._conn) or self._config and self._config.database or "default"
        RateLimit.check(key)
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
    if not res then
        error("Query failed: " .. tostring(err))
    end
    return res
end

function MySQL:mapType(column_type)
    local map = {
        string = "VARCHAR(" .. (column_type.length or 255) .. ")",
        text = "TEXT",
        mediumtext = "MEDIUMTEXT",
        longtext = "LONGTEXT",
        integer = "INTEGER",
        tinyint = "TINYINT",
        smallint = "SMALLINT",
        bigint = "BIGINT",
        float = "DOUBLE",
        decimal = "DECIMAL(" .. (column_type.precision or 10) .. "," .. (column_type.scale or 2) .. ")",
        boolean = "TINYINT(1)",
        timestamp = "TIMESTAMP",
        date = "DATE",
        datetime = "DATETIME",
        json = "JSON",
        cuid = "VARCHAR(25)",
        nanoid = "VARCHAR(21)",
        enum = "TEXT",
    }
    return map[column_type.type] or "TEXT"
end

function MySQL:dropTableCascade()
    return false
end

function MySQL:supportsAutoIncrement()
    return true
end

function MySQL:generateSelect(query)
    local sql = {}
    local bindings = {}

    local Encryption = require("jade.encryption")
    local columns = query._entity._columns

    -- SELECT clause with DISTINCT
    local select_prefix = "SELECT"
    if query._distinct then
        select_prefix = "SELECT DISTINCT"
    end

    if #query._select > 0 then
        local resolved = {}
        for _, item in ipairs(query._select) do
            -- Handle raw JSON expressions (jsonPath results)
            if type(item) == "table" and item._raw_json then
                local sql_part, part_bindings = Json.mySelectSql(
                    item._jsonColumn, item._pathSegments, item._asText
                )
                resolved[#resolved + 1] = sql_part
                for _, b in ipairs(part_bindings) do bindings[#bindings + 1] = b end
            else
                local part, part_bindings = Quoting.resolveSelectItem(item, function(name)
                    return self:quoteIdentifier(name)
                end)
                resolved[#resolved + 1] = part
                for _, b in ipairs(part_bindings) do
                    bindings[#bindings + 1] = b
                end
            end
        end
        sql[#sql + 1] = select_prefix .. " " .. table.concat(resolved, ", ")
    else
        -- SELECT * with decryption for encrypted columns
        local Encryption = require("jade.encryption")
        local entity_enabled = entity_name and Encryption.isEntityEnabled(entity_name) or Encryption.isEnabled()
        if entity_enabled then
            local fields = Encryption.getEncryptedFields(entity_name, columns)
            local has_encrypted = false
            for _ in pairs(fields) do has_encrypted = true; break end

            if has_encrypted then
                -- Build explicit column list with decryption
                local select_parts = {}
                for col_name, _ in pairs(columns) do
                    local col_ref = self:quoteIdentifier(col_name)
                    if fields[col_name] then
                        -- Encrypted column: wrap with AES_DECRYPT using session variable
                        select_parts[#select_parts + 1] = string.format(
                            "CAST(AES_DECRYPT(%s, @jade_encryption_key) AS CHAR) AS %s",
                            col_ref, col_ref
                        )
                    else
                        select_parts[#select_parts + 1] = col_ref
                    end
                end
                sql[#sql + 1] = select_prefix .. " " .. table.concat(select_parts, ", ")
            else
                sql[#sql + 1] = select_prefix .. " *"
            end
        else
            sql[#sql + 1] = select_prefix .. " *"
        end
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
            if type(col) == "table" and col._raw and col._raw._raw_json then
                -- JSON expression from jsonPath
                local sql_part, _ = Json.mySelectSql(
                    col._raw._jsonColumn, col._raw._pathSegments, col._raw._asText
                )
                group_parts[#group_parts + 1] = sql_part
            else
                local col_name = col
                if type(col) == "table" and col._column then
                    col_name = col._column
                end
                group_parts[#group_parts + 1] = self:quoteIdentifier(col_name)
            end
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
            if type(o) == "table" and o._raw and o._raw._raw_json then
                -- JSON expression from jsonPath
                local sql_part, _ = Json.mySelectSql(
                    o._raw._jsonColumn, o._raw._pathSegments, o._raw._asText
                )
                order_parts[#order_parts + 1] = sql_part .. " " .. o.dir
            else
                order_parts[#order_parts + 1] = self:quoteIdentifier(o.column) .. " " .. o.dir
            end
        end
        sql[#sql + 1] = "ORDER BY " .. table.concat(order_parts, ", ")
    end

    -- LIMIT clause
    if query._limit then
        sql[#sql + 1] = "LIMIT " .. tostring(query._limit)
    end

    -- OFFSET clause (only valid with LIMIT)
    if query._offset and query._limit then
        sql[#sql + 1] = "OFFSET " .. tostring(query._offset)
    end

    return table.concat(sql, " "), bindings
end

function MySQL:generateInsert(table_name, data, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}

    local Encryption = require("jade.encryption")
    local entity_enabled = entity and Encryption.isEntityEnabled(entity._table) or Encryption.isEnabled()
    local encrypt_cols = entity and entity._encrypt_cols or {}

    for key, value in pairs(data) do
        columns[#columns + 1] = self:quoteIdentifier(key)
        if encrypt_cols[key] and entity_enabled then
            -- Use MySQL AES_ENCRYPT with session variable
            placeholders[#placeholders + 1] = "AES_ENCRYPT(?, @jade_encryption_key)"
        else
            placeholders[#placeholders + 1] = "?"
        end
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

function MySQL:generateBulkInsert(table_name, rows, entity)
    if #rows == 0 then
        error("Cannot bulk insert zero rows")
    end

    local columns = {}
    local all_bindings = {}
    local value_sets = {}

    for key, _ in pairs(rows[1]) do
        columns[#columns + 1] = self:quoteIdentifier(key)
    end

    for _, row in ipairs(rows) do
        local placeholders = {}
        for _, col in ipairs(columns) do
            local key = col:gsub("`", "")
            placeholders[#placeholders + 1] = "?"
            all_bindings[#all_bindings + 1] = row[key]
        end
        value_sets[#value_sets + 1] = "(" .. table.concat(placeholders, ", ") .. ")"
    end

    local sql = string.format(
        "INSERT INTO %s (%s) VALUES %s",
        self:quoteIdentifier(table_name),
        table.concat(columns, ", "),
        table.concat(value_sets, ", ")
    )

    return sql, all_bindings
end

function MySQL:generateBulkUpdate(table_name, data, where)
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

function MySQL:generateBulkDelete(table_name, where)
    local where_sql, bindings = where:compile()

    local sql = string.format(
        "DELETE FROM %s WHERE %s",
        self:quoteIdentifier(table_name),
        where_sql
    )

    return sql, bindings
end

function MySQL:generateUpsert(table_name, data, conflict_columns, entity)
    local columns = {}
    local placeholders = {}
    local bindings = {}

    for key, value in pairs(data) do
        columns[#columns + 1] = self:quoteIdentifier(key)
        placeholders[#placeholders + 1] = "?"
        bindings[#bindings + 1] = value
    end

    local update_parts = {}
    for _, col in ipairs(columns) do
        local raw_col = col:gsub("`", "")
        local is_conflict = false
        for _, cc in ipairs(conflict_columns) do
            if raw_col == cc then
                is_conflict = true
                break
            end
        end
        if not is_conflict then
            update_parts[#update_parts + 1] = col .. " = VALUES(" .. col .. ")"
        end
    end

    local sql
    if #update_parts > 0 then
        sql = string.format(
            "INSERT INTO %s (%s) VALUES (%s) ON DUPLICATE KEY UPDATE %s",
            self:quoteIdentifier(table_name),
            table.concat(columns, ", "),
            table.concat(placeholders, ", "),
            table.concat(update_parts, ", ")
        )
    else
        sql = string.format(
            "INSERT IGNORE INTO %s (%s) VALUES (%s)",
            self:quoteIdentifier(table_name),
            table.concat(columns, ", "),
            table.concat(placeholders, ", ")
        )
    end

    return sql, bindings
end

function MySQL:generateUpdate(table_name, data, where, entity)
    local set_parts = {}
    local bindings = {}

    local Encryption = require("jade.encryption")
    local entity_enabled = entity and Encryption.isEntityEnabled(entity._table) or Encryption.isEnabled()
    local encrypt_cols = entity and entity._encrypt_cols or {}

    for key, value in pairs(data) do
        if encrypt_cols[key] and entity_enabled then
            set_parts[#set_parts + 1] = self:quoteIdentifier(key) .. " = AES_ENCRYPT(?, @jade_encryption_key)"
        else
            set_parts[#set_parts + 1] = self:quoteIdentifier(key) .. " = ?"
        end
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

function MySQL:generateDelete(table_name, where)
    local where_sql, bindings = where:compile()

    local sql = string.format(
        "DELETE FROM %s WHERE %s",
        self:quoteIdentifier(table_name),
        where_sql
    )

    return sql, bindings
end

function MySQL:getLastInsertId()
    self:_ensureConnected()
    local res, err = self._conn:execute("SELECT LAST_INSERT_ID() as id")
    if not res then
        error("Failed to get last insert id: " .. tostring(err))
    end
    local row = res:fetch({}, "a")
    return row and row.id
end

--- Execute a function within a database transaction.
-- Automatically commits on success, rolls back on error.
-- Uses the shared connection to ensure all operations are within the same transaction.
--
-- IMPORTANT MySQL LIMITATION: DDL statements (CREATE TABLE, DROP TABLE, ALTER TABLE,
-- TRUNCATE TABLE, RENAME TABLE) cause implicit commits in MySQL and CANNOT be rolled
-- back. If a migration contains DDL followed by DML and the DML fails, the DDL will
-- remain committed. This is a MySQL limitation, not a Jade bug.
-- PostgreSQL and SQLite support transactional DDL and are fully atomic.
--
-- @param fn function The function to execute within the transaction
-- @return boolean true if the transaction was committed successfully
function MySQL:transaction(fn)
    self:_ensureConnected()

    local conn = self._conn
    local res, err = conn:execute("START TRANSACTION")
    if not res then
        error("Failed to begin transaction: " .. tostring(err))
    end

    local ok, fn_err = pcall(fn)

    if ok then
        local commit_res, commit_err = conn:execute("COMMIT")
        if not commit_res then
            error("Failed to commit transaction: " .. tostring(commit_err))
        end
        return true
    else
        local rollback_res, rollback_err = conn:execute("ROLLBACK")
        if not rollback_res then
            -- Connection may be in undefined state after failed rollback
            self._conn = nil
            error("Failed to rollback transaction: " .. tostring(rollback_err) .. "\nOriginal error: " .. tostring(fn_err))
        end
        -- Re-raise original error preserving context
        error(fn_err, 2)
    end
end

return MySQL
