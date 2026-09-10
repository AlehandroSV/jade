local M = {}

-- Base error class
M.JadeError = require("jade.errors.base")

-- Error categories
M.ConnectionError = require("jade.errors.connection")
M.QueryError = require("jade.errors.query")
M.MigrationError = require("jade.errors.migration")
M.IntrospectionError = require("jade.errors.introspection")
M.IntegrityError = require("jade.errors.integrity")
M.SecurityError = require("jade.errors.security")
M.QueryTimeoutError = require("jade.errors.timeout")

-- Connection errors (J0xxx)
M.AUTHENTICATION_FAILED = "J0001"
M.CONNECTION_REFUSED = "J0002"
M.CONNECTION_TIMEOUT = "J0003"
M.DATABASE_NOT_FOUND = "J0004"
M.CONFIG_MISSING = "J0005"
M.CONFIG_INVALID = "J0006"
M.DRIVER_NOT_FOUND = "J0007"
M.DRIVER_NOT_SUPPORTED = "J0008"
M.CONNECTION_POOL_EXHAUSTED = "J0009"
M.TLS_ERROR = "J0010"

-- Query errors (J1xxx)
M.QUERY_SYNTAX_ERROR = "J1000"
M.QUERY_TIMEOUT = "J1001"
M.QUERY_TOO_COMPLEX = "J1002"
M.COLUMN_NOT_FOUND = "J1003"
M.TABLE_NOT_FOUND = "J1004"
M.VALUE_TOO_LONG = "J1005"
M.TYPE_MISMATCH = "J1006"
M.MISSING_REQUIRED_FIELD = "J1007"
M.NO_ROWS_FOUND = "J1008"
M.MULTIPLE_ROWS_FOUND = "J1009"
M.INSERT_FAILED = "J1010"
M.UPDATE_FAILED = "J1011"
M.DELETE_FAILED = "J1012"
M.RAW_QUERY_FAILED = "J1013"
M.RESULT_SET_TOO_LARGE = "J1014"
M.NULL_CONSTRAINT_VIOLATION = "J1015"
M.UNIQUE_CONSTRAINT_VIOLATION = "J1016"
M.FOREIGN_KEY_VIOLATION = "J1017"
M.CHECK_CONSTRAINT_VIOLATION = "J1018"
M.DATA_VALIDATION_ERROR = "J1019"
M.VALUE_OUT_OF_RANGE = "J1020"

-- Migration errors (J2xxx)
M.MIGRATION_FAILED = "J2000"
M.MIGRATION_ROLLBACK_FAILED = "J2001"
M.MIGRATION_ALREADY_APPLIED = "J2002"
M.MIGRATION_NOT_FOUND = "J2003"
M.MIGRATION_FILE_INVALID = "J2004"
M.MIGRATION_TABLE_NOT_FOUND = "J2005"
M.MIGRATION_LOCKED = "J2006"
M.MIGRATION_DEPENDENCY_MISSING = "J2007"
M.DESTRUCTIVE_MIGRATION = "J2008"
M.SCHEMA_INCONSISTENT = "J2009"
M.SHADOW_DATABASE_ERROR = "J2010"

-- Introspection errors (J3xxx)
M.INTROSPECTION_FAILED = "J3000"
M.DATABASE_EMPTY = "J3001"
M.SCHEMA_INCONSISTENT_INTROSPECTION = "J3002"
M.UNSUPPORTED_TYPE = "J3003"
M.CONVERSION_FAILED = "J3004"

-- Integrity / transaction errors (J4xxx) — constraints live in J1xxx
M.PRIMARY_KEY_VIOLATION = "J4004"
M.CONCURRENT_UPDATE = "J4005"
M.TRANSACTION_FAILED = "J4006"
M.DEADLOCK_DETECTED = "J4007"

-- Deprecated aliases (prefer J1xxx constraint codes)
M.UNIQUE_VIOLATION = M.UNIQUE_CONSTRAINT_VIOLATION
M.FOREIGN_KEY_VIOLATION_INTEGRITY = M.FOREIGN_KEY_VIOLATION
M.NOT_NULL_VIOLATION = M.NULL_CONSTRAINT_VIOLATION
M.CHECK_VIOLATION = M.CHECK_CONSTRAINT_VIOLATION
M.ROW_NOT_FOUND = M.NO_ROWS_FOUND

-- Security errors (J5xxx)
M.SQL_INJECTION_DETECTED = "J5000"
M.INVALID_IDENTIFIER = "J5001"
M.QUERY_TOO_LONG = "J5002"
M.TOO_MANY_PARAMETERS = "J5003"
M.INVALID_INPUT = "J5004"
M.INPUT_TOO_LONG = "J5005"
M.RATE_LIMIT_EXCEEDED = "J5006"
M.UNAUTHORIZED_ACCESS = "J5007"
M.PERMISSION_DENIED = "J5008"

-- Error messages (EN)
M.messages = {
    -- Connection
    [M.AUTHENTICATION_FAILED] = "Authentication failed against database server at '{host}'. Invalid credentials for user '{user}'.",
    [M.CONNECTION_REFUSED] = "Can't reach database server at '{host}:{port}'. Please make sure your database server is running.",
    [M.CONNECTION_TIMEOUT] = "Connection timed out at '{host}:{port}' after {timeout}ms.",
    [M.DATABASE_NOT_FOUND] = "Database '{database}' does not exist on the server '{host}:{port}'.",
    [M.CONFIG_MISSING] = "Configuration file not found: '{path}'.",
    [M.CONFIG_INVALID] = "Invalid configuration: {details}",
    [M.DRIVER_NOT_FOUND] = "Driver '{driver}' not found. Available drivers: {available}",
    [M.DRIVER_NOT_SUPPORTED] = "Driver '{driver}' is not supported for this operation.",
    [M.CONNECTION_POOL_EXHAUSTED] = "Connection pool exhausted. Maximum {limit} connections reached.",
    [M.TLS_ERROR] = "Error establishing TLS connection: {message}",

    -- Query
    [M.QUERY_SYNTAX_ERROR] = "Query syntax error: {error} at position {position}",
    [M.QUERY_TIMEOUT] = "Query timed out after {timeout}ms.",
    [M.QUERY_TOO_COMPLEX] = "Query too complex to process.",
    [M.COLUMN_NOT_FOUND] = "Column '{column}' does not exist in table '{table}'.",
    [M.TABLE_NOT_FOUND] = "Table '{table}' does not exist in the database.",
    [M.VALUE_TOO_LONG] = "Value too long for column '{column}'. Maximum: {max} characters.",
    [M.TYPE_MISMATCH] = "Invalid type for field '{field}'. Expected: {expected}, received: {received}.",
    [M.MISSING_REQUIRED_FIELD] = "Required field '{field}' not provided.",
    [M.NO_ROWS_FOUND] = "No records found in table '{table}'.",
    [M.MULTIPLE_ROWS_FOUND] = "Multiple records found when only one was expected.",
    [M.INSERT_FAILED] = "Failed to insert record: {error}",
    [M.UPDATE_FAILED] = "Failed to update record: {error}",
    [M.DELETE_FAILED] = "Failed to delete record: {error}",
    [M.RAW_QUERY_FAILED] = "Raw query failed. Code: {code}. Message: {message}",
    [M.RESULT_SET_TOO_LARGE] = "Result set too large. Use limit() to reduce.",
    [M.NULL_CONSTRAINT_VIOLATION] = "NULL constraint violation on column '{column}'.",
    [M.UNIQUE_CONSTRAINT_VIOLATION] = "Unique constraint violation: {constraint}",
    [M.FOREIGN_KEY_VIOLATION] = "Foreign key constraint violation on field '{field}'.",
    [M.CHECK_CONSTRAINT_VIOLATION] = "CHECK constraint violation: {constraint}",
    [M.DATA_VALIDATION_ERROR] = "Data validation error: {error}",
    [M.VALUE_OUT_OF_RANGE] = "Value out of range for type. {details}",

    -- Migration
    [M.MIGRATION_FAILED] = "Failed to execute migration '{name}': {error}",
    [M.MIGRATION_ROLLBACK_FAILED] = "Failed to rollback migration '{name}': {error}",
    [M.MIGRATION_ALREADY_APPLIED] = "Migration '{name}' has already been applied.",
    [M.MIGRATION_NOT_FOUND] = "Migration '{name}' not found.",
    [M.MIGRATION_FILE_INVALID] = "Invalid migration file: {error}",
    [M.MIGRATION_TABLE_NOT_FOUND] = "Migration tracking table not found.",
    [M.MIGRATION_LOCKED] = "Migration locked by another operation.",
    [M.MIGRATION_DEPENDENCY_MISSING] = "Required migration '{name}' has not been applied.",
    [M.DESTRUCTIVE_MIGRATION] = "Migration may cause data loss: {details}",
    [M.SCHEMA_INCONSISTENT] = "Inconsistent schema: {details}",
    [M.SHADOW_DATABASE_ERROR] = "Shadow database error: {error}",

    -- Introspection
    [M.INTROSPECTION_FAILED] = "Failed to introspect database: {error}",
    [M.DATABASE_EMPTY] = "Introspected database is empty.",
    [M.SCHEMA_INCONSISTENT_INTROSPECTION] = "Inconsistent database schema: {details}",
    [M.UNSUPPORTED_TYPE] = "Type '{type}' is not supported for introspection.",
    [M.CONVERSION_FAILED] = "Failed to convert database schema: {error}",

    -- Integrity / transaction
    [M.PRIMARY_KEY_VIOLATION] = "PRIMARY KEY violation on table '{table}'.",
    [M.CONCURRENT_UPDATE] = "Concurrent update conflict. Record modified by another operation.",
    [M.TRANSACTION_FAILED] = "Transaction failed: {error}",
    [M.DEADLOCK_DETECTED] = "Deadlock detected. Please retry.",

    -- Security
    [M.SQL_INJECTION_DETECTED] = "SQL injection attempt detected: {pattern}",
    [M.INVALID_IDENTIFIER] = "Invalid identifier (possible injection): '{identifier}'",
    [M.QUERY_TOO_LONG] = "Query exceeds maximum length of {max} characters.",
    [M.TOO_MANY_PARAMETERS] = "Too many parameters: {count} (maximum: {max})",
    [M.INVALID_INPUT] = "Invalid input: {details}",
    [M.INPUT_TOO_LONG] = "Input exceeds maximum length of {max} characters.",
    [M.RATE_LIMIT_EXCEEDED] = "Rate limit exceeded.",
    [M.UNAUTHORIZED_ACCESS] = "Unauthorized access.",
    [M.PERMISSION_DENIED] = "Permission denied for this operation.",
}

local FACTORY_BY_PREFIX = {
    ["0"] = "ConnectionError",
    ["1"] = "QueryError",
    ["2"] = "MigrationError",
    ["3"] = "IntrospectionError",
    ["4"] = "IntegrityError",
    ["5"] = "SecurityError",
}

-- Get error message with details
function M.getMessage(code, details)
    local template = M.messages[code]
    if not template then
        return "Unknown error: " .. tostring(code)
    end

    if not details then
        return template
    end

    local result = template
    for key, value in pairs(details) do
        result = result:gsub("{" .. key .. "}", tostring(value))
    end
    return result
end

--- Build a typed error object without raising it.
---@param code string Jade error code (J0xxx–J5xxx)
---@param details table|nil Placeholders for the message template
---@return JadeError
function M.build(code, details)
    local prefix = tostring(code):sub(2, 2)
    local factory_name = FACTORY_BY_PREFIX[prefix]
    if not factory_name then
        return M.JadeError.new(code, M.getMessage(code, details), details)
    end
    return M[factory_name](code, details)
end

--- Raise a typed Jade error. Catch with pcall; inspect err.code / err.message.
---@param code string Jade error code
---@param details table|nil Message placeholders
---@param level number|nil error() level (default 2 = caller)
function M.raise(code, details, level)
    error(M.build(code, details), (level or 2) + 1)
end

--- Map a driver/native error string to a Jade error code.
--- Best-effort heuristic for PostgreSQL/MySQL/SQLite/luasql messages.
---@param err any Native driver error
---@return string code
function M.classifyDriverError(err)
    local msg = tostring(err):lower()
    if msg:find("password authentication failed", 1, true)
        or msg:find("access denied", 1, true)
        or msg:find("authentication failed", 1, true) then
        return M.AUTHENTICATION_FAILED
    end
    if msg:find("connection refused", 1, true)
        or msg:find("could not connect", 1, true)
        or msg:find("unable to open database file", 1, true) then
        return M.CONNECTION_REFUSED
    end
    if msg:find("timeout", 1, true) or msg:find("timed out", 1, true) then
        return M.CONNECTION_TIMEOUT
    end
    if msg:find("does not exist", 1, true)
        or msg:find("unknown database", 1, true)
        or msg:find("no such database", 1, true) then
        return M.DATABASE_NOT_FOUND
    end
    if msg:find("ssl", 1, true) or msg:find("tls", 1, true) then
        return M.TLS_ERROR
    end
    if msg:find("unique", 1, true) or msg:find("duplicate", 1, true) then
        return M.UNIQUE_CONSTRAINT_VIOLATION
    end
    if msg:find("foreign key", 1, true) then
        return M.FOREIGN_KEY_VIOLATION
    end
    if msg:find("not-null", 1, true) or msg:find("not null", 1, true) then
        return M.NULL_CONSTRAINT_VIOLATION
    end
    if msg:find("deadlock", 1, true) then
        return M.DEADLOCK_DETECTED
    end
    if msg:find("syntax error", 1, true) then
        return M.QUERY_SYNTAX_ERROR
    end
    if msg:find("no such table", 1, true) or msg:find("doesn't exist", 1, true) then
        return M.TABLE_NOT_FOUND
    end
    if msg:find("no such column", 1, true) or msg:find("unknown column", 1, true) then
        return M.COLUMN_NOT_FOUND
    end
    return M.RAW_QUERY_FAILED
end

-- Create error by category
function M.ConnectionError(code, details)
    return require("jade.errors.connection").new(code, M.getMessage(code, details), details)
end

function M.QueryError(code, details)
    return require("jade.errors.query").new(code, M.getMessage(code, details), details)
end

function M.MigrationError(code, details)
    return require("jade.errors.migration").new(code, M.getMessage(code, details), details)
end

function M.IntrospectionError(code, details)
    return require("jade.errors.introspection").new(code, M.getMessage(code, details), details)
end

function M.IntegrityError(code, details)
    return require("jade.errors.integrity").new(code, M.getMessage(code, details), details)
end

function M.SecurityError(code, details)
    return require("jade.errors.security").new(code, M.getMessage(code, details), details)
end

return M
