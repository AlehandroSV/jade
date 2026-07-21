local Quoting = {}

--- Quotes an identifier (table name, column name) to prevent conflicts with reserved words.
--- @param name string The identifier to quote
--- @return string The quoted identifier
function Quoting.quoteIdentifier(name)
    return '"' .. name:gsub('"', '""') .. '"'
end

--- Quotes multiple identifiers in a comma-separated string.
--- @param names table Array of identifiers
--- @return string Comma-separated quoted identifiers
function Quoting.quoteIdentifiers(names)
    local quoted = {}
    for i, name in ipairs(names) do
        quoted[i] = Quoting.quoteIdentifier(name)
    end
    return table.concat(quoted, ", ")
end

--- Resolves a select item to an SQL string fragment.
--- Handles plain strings, Expression aliases, and subquery aliases.
--- @param item string|table The select item
--- @param quoteFn function|nil Optional quoting function (defaults to quoteIdentifier)
--- @return string, table The resolved SQL fragment and any bindings
function Quoting.resolveSelectItem(item, quoteFn)
    quoteFn = quoteFn or Quoting.quoteIdentifier
    if type(item) == "string" then
        -- Validate the string item to prevent SQL injection
        -- Allow: simple column names, table.column, and known SQL functions
        local upper = item:upper()
        -- Block dangerous patterns
        if item:match(";") then
            error("Invalid SELECT item: contains semicolon")
        end
        if item:match("%-%-") then
            error("Invalid SELECT item: contains comment")
        end
        if item:match("/%*") then
            error("Invalid SELECT item: contains block comment")
        end
        -- Allow simple column names (possibly with table prefix)
        if item:match("^[%a_][%w_]*%.?[%w_]*$") then
            return item, {}
        end
        -- Allow common SQL aggregate/scalar functions
        local allowed_functions = {
            "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF",
            "UPPER", "LOWER", "TRIM", "LENGTH", "SUBSTRING", "CAST",
            "EXTRACT", "NOW", "CURRENT_TIMESTAMP",
        }
        for _, fn in ipairs(allowed_functions) do
            if upper:match("^%s*" .. fn .. "%s*%(") then
                return item, {}
            end
        end
        -- Allow DISTINCT keyword
        if upper:match("^%s*DISTINCT%s+") then
            return item, {}
        end
        -- Reject anything else
        error("Invalid SELECT item: " .. item)
    elseif type(item) == "table" then
        -- Expression with alias: table.column AS alias
        if item._column and item._alias then
            if item._table and item._table ~= "" then
                return quoteFn(item._table) .. "." .. quoteFn(item._column) .. " AS " .. quoteFn(item._alias), {}
            else
                return quoteFn(item._column) .. " AS " .. quoteFn(item._alias), {}
            end
        -- Subquery with alias: (SELECT ...) AS alias
        elseif item._query and item._alias then
            local sub_sql, sub_bindings = item._query:toSQL()
            return "(" .. sub_sql .. ") AS " .. quoteFn(item._alias), sub_bindings or {}
        end
    end
    return tostring(item), {}
end

return Quoting
