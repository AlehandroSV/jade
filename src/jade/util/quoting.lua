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
        return item, {}
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
