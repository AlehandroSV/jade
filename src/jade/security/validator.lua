local errors = require("jade.errors")

local M = {}

-- Maximum query length (prevent memory exhaustion)
M.MAX_QUERY_LENGTH = 100000

-- Maximum parameter count
M.MAX_PARAMETERS = 1000

-- Maximum string length
M.MAX_STRING_LENGTH = 65536

-- Maximum IN clause items
M.MAX_IN_ITEMS = 1000

-- Validate query length
function M.validateQueryLength(sql)
    if #sql > M.MAX_QUERY_LENGTH then
        errors.raise(errors.QUERY_TOO_LONG, {
            max = M.MAX_QUERY_LENGTH,
        }, 2)
    end
    return true
end

-- Validate parameter count
function M.validateParameterCount(bindings)
    if bindings and #bindings > M.MAX_PARAMETERS then
        errors.raise(errors.TOO_MANY_PARAMETERS, {
            count = #bindings,
            max = M.MAX_PARAMETERS,
        }, 2)
    end
    return true
end

-- Validate string length
function M.validateStringLength(value, max_length)
    max_length = max_length or M.MAX_STRING_LENGTH
    if type(value) == "string" and #value > max_length then
        errors.raise(errors.INPUT_TOO_LONG, {
            max = max_length,
        }, 2)
    end
    return true
end

-- Validate IN clause
function M.validateInClause(values)
    if type(values) ~= "table" then
        errors.raise(errors.INVALID_INPUT, {
            details = "IN clause requires a table",
        }, 2)
    end
    if #values > M.MAX_IN_ITEMS then
        errors.raise(errors.TOO_MANY_PARAMETERS, {
            count = #values,
            max = M.MAX_IN_ITEMS,
        }, 2)
    end
    return true
end

-- Validate column name (prevent injection through identifiers)
function M.validateColumnName(name)
    if type(name) ~= "string" then
        errors.raise(errors.INVALID_INPUT, {
            details = "Column name must be a string",
        }, 2)
    end

    -- Allow only alphanumeric and underscore
    if not name:match("^[%a_][%w_]*$") then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end

    -- Check length
    if #name > 64 then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end

    return true
end

-- Validate table name
function M.validateTableName(name)
    if type(name) ~= "string" then
        errors.raise(errors.INVALID_INPUT, {
            details = "Table name must be a string",
        }, 2)
    end

    -- Allow only alphanumeric and underscore
    if not name:match("^[%a_][%w_]*$") then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end

    -- Check length
    if #name > 64 then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end

    return true
end

-- Validate order direction
function M.validateOrderDirection(direction)
    local valid = { ASC = true, DESC = true, asc = true, desc = true }
    if not valid[direction] then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid order direction: " .. tostring(direction),
        }, 2)
    end
    return true
end

-- Validate pagination parameters
function M.validatePagination(page, per_page)
    if page and (type(page) ~= "number" or page < 1) then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid page number: " .. tostring(page),
        }, 2)
    end
    if per_page and (type(per_page) ~= "number" or per_page < 1 or per_page > 1000) then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid per_page value: " .. tostring(per_page),
        }, 2)
    end
    return true
end

-- Validate LIMIT value (must be a non-negative integer)
function M.validateLimit(value)
    if value == nil then return true end
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid LIMIT value: " .. tostring(value),
        }, 2)
    end
    return true
end

-- Validate OFFSET value (must be a non-negative integer)
function M.validateOffset(value)
    if value == nil then return true end
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid OFFSET value: " .. tostring(value),
        }, 2)
    end
    return true
end

-- Validate JOIN table name
function M.validateJoinTableName(name)
    if type(name) ~= "string" then
        errors.raise(errors.INVALID_INPUT, {
            details = "JOIN table name must be a string",
        }, 2)
    end
    -- Allow alphanumeric and underscore, also dots for schema.table
    if not name:match("^[%a_][%w_%.]*$") then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end
    if #name > 128 then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = name,
        }, 2)
    end
    return true
end

-- Validate SELECT item (must be a string or table with _column/_query)
function M.validateSelectItem(item)
    if type(item) == "string" then
        -- Allow SQL functions and expressions that are whitelisted
        -- Block obviously dangerous patterns
        local upper = item:upper()
        if upper:match(";%s*") then
            errors.raise(errors.SQL_INJECTION_DETECTED, {
                pattern = ";",
            }, 2)
        end
        if upper:match("%-%-") then
            errors.raise(errors.SQL_INJECTION_DETECTED, {
                pattern = "--",
            }, 2)
        end
        if upper:match("/%*") then
            errors.raise(errors.SQL_INJECTION_DETECTED, {
                pattern = "/*",
            }, 2)
        end
        -- Allow common SQL functions
        local allowed_patterns = {
            "^%s*%*$",     -- wildcard select: *
            "^%s*COUNT%s*%(",
            "^%s*SUM%s*%(",
            "^%s*AVG%s*%(",
            "^%s*MIN%s*%(",
            "^%s*MAX%s*%(",
            "^%s*DISTINCT%s+",
            "^[%w_%.]+$",  -- simple column name or table.column
        }
        for _, pattern in ipairs(allowed_patterns) do
            if item:match(pattern) then
                return true
            end
        end
        -- If no pattern matched, reject
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid SELECT item: " .. item,
        }, 2)
    elseif type(item) == "table" then
        -- Expression with alias or subquery — validated at compile time
        return true
    else
        errors.raise(errors.INVALID_INPUT, {
            details = "SELECT item must be a string or expression table",
        }, 2)
    end
end

-- Validate ORDER BY direction
function M.validateOrderByDirection(direction)
    local valid = { ASC = true, DESC = true, asc = true, desc = true, [""] = true }
    if not valid[direction] then
        errors.raise(errors.INVALID_INPUT, {
            details = "Invalid ORDER BY direction: " .. tostring(direction),
        }, 2)
    end
    return true
end

-- Validate ORDER BY column (prevent injection through column name)
function M.validateOrderByColumn(column)
    if type(column) ~= "string" then
        -- Allow expression objects
        if type(column) == "table" then
            return true
        end
        errors.raise(errors.INVALID_INPUT, {
            details = "ORDER BY column must be a string or expression",
        }, 2)
    end
    -- Allow column names with dots for table.column
    if not column:match("^[%a_][%w_%.]*$") then
        errors.raise(errors.INVALID_IDENTIFIER, {
            identifier = column,
        }, 2)
    end
    return true
end

return M
