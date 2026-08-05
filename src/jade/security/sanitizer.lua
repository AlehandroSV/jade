local M = {}

-- Dangerous SQL keywords that should not appear in user input
local DANGEROUS_KEYWORDS = {
    "DROP", "DELETE", "TRUNCATE", "ALTER", "CREATE", "INSERT",
    "UPDATE", "EXEC", "EXECUTE", "DECLARE", "CURSOR", "OPEN",
    "CLOSE", "DEALLOCATE", "PREPARE", "GRANT", "REVOKE",
    "COMMIT", "ROLLBACK", "SAVEPOINT", "SET", "RESET",
}

--- Check if string contains SQL injection attempts.
-- WARNING: This function uses regex/keyword-based detection which is inherently
-- incomplete and can be bypassed by experienced attackers (e.g., via CHAR(),
-- hex encoding, unicode, comment obfuscation, etc.).
--
-- The primary protection against SQL injection should be:
-- 1. Prepared statements/parameterized queries for ALL values
-- 2. Whitelist validation for identifiers (column/table names)
--
-- This function is provided as a convenience for additional validation layers,
-- but should NOT be relied upon as the sole protection against SQL injection.
--
-- @param input string The input to check
-- @return boolean, string true if suspicious pattern found, reason string
function M.detectSQLInjection(input)
    if type(input) ~= "string" then
        return false
    end

    local upper = input:upper()

    -- Check for common SQL injection patterns
    local patterns = {
        "['\"]%s*OR%s+['\"]",           -- ' OR '1'='1
        "['\"]%s*AND%s+['\"]",          -- ' AND '1'='1
        ";%s*DROP",                     -- ; DROP TABLE
        ";%s*DELETE",                   -- ; DELETE FROM
        ";%s*UPDATE",                   -- ; UPDATE
        ";%s*INSERT",                   -- ; INSERT INTO
        "%-%-",                         -- SQL comment
        "/%*",                          -- SQL block comment
        "UNION%s+ALL%s+SELECT",        -- UNION ALL SELECT
        "UNION%s+SELECT",              -- UNION SELECT
        "INTO%s+OUTFILE",              -- INTO OUTFILE (file write)
        "INTO%s+DUMPFILE",             -- INTO DUMPFILE
        "LOAD_FILE",                    -- LOAD_FILE
        "BENCHMARK",                    -- BENCHMARK (timing attack)
        "SLEEP",                        -- SLEEP (timing attack)
        "WAITFOR%s+DELAY",             -- WAITFOR DELAY (MSSQL)
    }

    for _, pattern in ipairs(patterns) do
        if upper:match(pattern) then
            return true, "Suspicious pattern detected: " .. pattern
        end
    end

    -- Check for dangerous keywords followed by space (not part of a word)
    for _, keyword in ipairs(DANGEROUS_KEYWORDS) do
        if upper:match(keyword .. "%s") or upper:match(keyword .. "$") then
            -- Allow if it's inside a string literal (between quotes)
            local before = upper:sub(1, upper:find(keyword) - 1)
            local quote_count = 0
            for _ in before:gmatch("'") do
                quote_count = quote_count + 1
            end
            if quote_count % 2 == 0 then
                return true, "Dangerous SQL keyword detected: " .. keyword
            end
        end
    end

    return false
end

-- Sanitize string input
function M.sanitizeString(input)
    if type(input) ~= "string" then
        return input
    end

    -- Remove null bytes
    local sanitized = input:gsub("%z", "")

    -- Trim whitespace
    sanitized = sanitized:match("^%s*(.-)%s*$")

    return sanitized
end

-- Validate input type
function M.validateType(value, expected_type)
    if value == nil then
        return true -- nil is valid for optional fields
    end

    local type_map = {
        string = "string",
        integer = "number",
        float = "number",
        decimal = "number",
        boolean = "boolean",
        text = "string",
        timestamp = "string",
        date = "string",
        uuid = "string",
        json = "table",
    }

    local lua_type = type_map[expected_type]
    if not lua_type then
        return true -- Unknown type, skip validation
    end

    if lua_type == "number" then
        -- Integer type requires whole number, float/decimal accept any number
        if expected_type == "integer" then
            return type(value) == "number" and value == math.floor(value)
        end
        return type(value) == "number"
    end

    return type(value) == lua_type
end

-- Escape SQL identifier (table/column name).
-- Uses strict whitelist validation to ensure only valid identifiers are allowed.
-- The pattern ^[%a_][%w_]*$ ensures identifiers contain only letters, digits, and
-- underscores, starting with a letter or underscore. This inherently prevents
-- SQL injection without needing regex-based detection.
-- @param identifier string The identifier to validate
-- @return string The validated identifier
function M.escapeIdentifier(identifier)
    if type(identifier) ~= "string" then
        error("Identifier must be a string")
    end

    -- Strict whitelist: only alphanumeric characters and underscores
    -- Must start with a letter or underscore
    if not identifier:match("^[%a_][%w_]*$") then
        error("Invalid identifier: " .. identifier)
    end

    return identifier
end

-- Escape string value for SQL (with quotes).
-- NOTE: This function should only be used as a last resort for raw SQL construction.
-- The recommended approach is to use prepared statements (bindings) for ALL values.
-- SQL injection detection has been removed because it gives a false sense of security
-- and can be bypassed by experienced attackers.
-- @see driver:execute(sql, bindings) for the safe alternative
function M.escapeString(value)
    if value == nil then
        return "NULL"
    end

    if type(value) ~= "string" then
        return tostring(value)
    end

    -- Escape single quotes (standard SQL escaping)
    local escaped = value:gsub("'", "''")

    return "'" .. escaped .. "'"
end

-- Escape value based on type
function M.escapeValue(value, column_type)
    if value == nil then
        return "NULL"
    end

    if column_type == "string" or column_type == "text" or column_type == "uuid" then
        return M.escapeString(value)
    elseif column_type == "integer" or column_type == "float" or column_type == "decimal" then
        if type(value) ~= "number" then
            error("Expected number, got " .. type(value))
        end
        return tostring(value)
    elseif column_type == "boolean" then
        if type(value) ~= "boolean" then
            error("Expected boolean, got " .. type(value))
        end
        return value and "TRUE" or "FALSE"
    elseif column_type == "timestamp" or column_type == "date" then
        return M.escapeString(value)
    else
        return M.escapeString(value)
    end
end

return M