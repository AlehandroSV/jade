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
        error("Query exceeds maximum length: " .. #sql .. " > " .. M.MAX_QUERY_LENGTH)
    end
    return true
end

-- Validate parameter count
function M.validateParameterCount(bindings)
    if bindings and #bindings > M.MAX_PARAMETERS then
        error("Too many parameters: " .. #bindings .. " > " .. M.MAX_PARAMETERS)
    end
    return true
end

-- Validate string length
function M.validateStringLength(value, max_length)
    max_length = max_length or M.MAX_STRING_LENGTH
    if type(value) == "string" and #value > max_length then
        error("String exceeds maximum length: " .. #value .. " > " .. max_length)
    end
    return true
end

-- Validate IN clause
function M.validateInClause(values)
    if type(values) ~= "table" then
        error("IN clause requires a table")
    end
    if #values > M.MAX_IN_ITEMS then
        error("IN clause has too many items: " .. #values .. " > " .. M.MAX_IN_ITEMS)
    end
    return true
end

-- Validate column name (prevent injection through identifiers)
function M.validateColumnName(name)
    if type(name) ~= "string" then
        error("Column name must be a string")
    end

    -- Allow only alphanumeric and underscore
    if not name:match("^[%a_][%w_]*$") then
        error("Invalid column name: " .. name)
    end

    -- Check length
    if #name > 64 then
        error("Column name too long: " .. #name)
    end

    return true
end

-- Validate table name
function M.validateTableName(name)
    if type(name) ~= "string" then
        error("Table name must be a string")
    end

    -- Allow only alphanumeric and underscore
    if not name:match("^[%a_][%w_]*$") then
        error("Invalid table name: " .. name)
    end

    -- Check length
    if #name > 64 then
        error("Table name too long: " .. #name)
    end

    return true
end

-- Validate order direction
function M.validateOrderDirection(direction)
    local valid = { ASC = true, DESC = true, asc = true, desc = true }
    if not valid[direction] then
        error("Invalid order direction: " .. tostring(direction))
    end
    return true
end

-- Validate pagination parameters
function M.validatePagination(page, per_page)
    if page and (type(page) ~= "number" or page < 1) then
        error("Invalid page number: " .. tostring(page))
    end
    if per_page and (type(per_page) ~= "number" or per_page < 1 or per_page > 1000) then
        error("Invalid per_page value: " .. tostring(per_page))
    end
    return true
end

-- Validate LIMIT value (must be a non-negative integer)
function M.validateLimit(value)
    if value == nil then return true end
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        error("Invalid LIMIT value: " .. tostring(value))
    end
    return true
end

-- Validate OFFSET value (must be a non-negative integer)
function M.validateOffset(value)
    if value == nil then return true end
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        error("Invalid OFFSET value: " .. tostring(value))
    end
    return true
end

-- Validate JOIN table name
function M.validateJoinTableName(name)
    if type(name) ~= "string" then
        error("JOIN table name must be a string")
    end
    -- Allow alphanumeric and underscore, also dots for schema.table
    if not name:match("^[%a_][%w_%.]*$") then
        error("Invalid JOIN table name: " .. name)
    end
    if #name > 128 then
        error("JOIN table name too long: " .. #name)
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
            error("Invalid SELECT item: contains semicolon")
        end
        if upper:match("%-%-") then
            error("Invalid SELECT item: contains comment")
        end
        if upper:match("/%*") then
            error("Invalid SELECT item: contains block comment")
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
        error("Invalid SELECT item: " .. item)
    elseif type(item) == "table" then
        -- Expression with alias or subquery — validated at compile time
        return true
    else
        error("SELECT item must be a string or expression table")
    end
end

-- Validate ORDER BY direction
function M.validateOrderByDirection(direction)
    local valid = { ASC = true, DESC = true, asc = true, desc = true, [""] = true }
    if not valid[direction] then
        error("Invalid ORDER BY direction: " .. tostring(direction))
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
        error("ORDER BY column must be a string or expression")
    end
    -- Allow column names with dots for table.column
    if not column:match("^[%a_][%w_%.]*$") then
        error("Invalid ORDER BY column: " .. column)
    end
    return true
end

return M
