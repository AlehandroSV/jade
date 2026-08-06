local M = {}

-- Sanitizer module
M.sanitizer = require("jade.security.sanitizer")

-- Validator module
M.validator = require("jade.security.validator")

-- Initialize security module
function M.init(options)
    options = options or {}

    -- Set limits
    if options.max_query_length then
        M.validator.MAX_QUERY_LENGTH = options.max_query_length
    end

    if options.max_parameters then
        M.validator.MAX_PARAMETERS = options.max_parameters
    end

    if options.max_string_length then
        M.validator.MAX_STRING_LENGTH = options.max_string_length
    end

    if options.max_in_items then
        M.validator.MAX_IN_ITEMS = options.max_in_items
    end
end

-- Validate input data for entity create/update
-- data: the input data table
-- columns: entity column definitions
--
-- Security approach:
-- - Column names validated via whitelist (validator.validateColumnName)
-- - Values are passed via prepared statements (bindings) - no SQL injection possible
-- - Type validation ensures correct data types
-- - String length validation prevents buffer overflow attacks
--
-- NOTE: SQL injection detection via regex has been removed from value validation.
-- The real protection comes from using prepared statements (bindings) for ALL values,
-- not from regex-based detection which can be bypassed.
function M.validateInput(data, columns)
    if not data or not columns then
        return true
    end

    for key, value in pairs(data) do
        -- Validate column name (whitelist approach - inherently safe)
        M.validator.validateColumnName(key)

        -- Find column definition
        local col_def = columns[key]
        if col_def then
            -- Validate type
            if not M.sanitizer.validateType(value, col_def.type) then
                error("Type mismatch for column '" .. key .. "': expected " .. col_def.type)
            end

            -- Validate string length
            if type(value) == "string" and col_def.length then
                M.validator.validateStringLength(value, col_def.length)
            end
        end
    end

    return true
end

-- Validate a select item before adding to query
function M.validateSelectItem(item)
    return M.validator.validateSelectItem(item)
end

-- Validate a JOIN table name
function M.validateJoinTableName(name)
    return M.validator.validateJoinTableName(name)
end

-- Validate ORDER BY column and direction
function M.validateOrderBy(column, direction)
    M.validator.validateOrderByColumn(column)
    M.validator.validateOrderByDirection(direction)
    return true
end

-- Validate LIMIT value
function M.validateLimit(value)
    return M.validator.validateLimit(value)
end

-- Validate OFFSET value
function M.validateOffset(value)
    return M.validator.validateOffset(value)
end

-- Validate query length and parameter count
function M.validateQuery(sql, bindings)
    M.validator.validateQueryLength(sql)
    if bindings then
        M.validator.validateParameterCount(bindings)
    end
    return true
end

return M
