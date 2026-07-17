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

return Quoting
