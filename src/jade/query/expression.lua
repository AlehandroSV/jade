--- @class Jade.Expression : table
--- @field _column string Column name
--- @field _table? string Table name
local Expression = {}
Expression.__index = Expression

--- Create a new Expression bound to a column
--- @param column_name string Column name
--- @param table_name? string Target table name
--- @return Jade.Expression Expression instance for chaining
function Expression.new(column_name, table_name)
    return setmetatable({
        _column = column_name,
        _table = table_name,
    }, Expression)
end

--- Equality comparison (column = value)
--- @param value any Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:eq(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "=", val, self._table)
end

--- Less than comparison (column < value)
--- @param value number|Jade.Value Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:lt(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "<", val, self._table)
end

--- Less than or equal (column <= value)
--- @param value number|Jade.Value Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:le(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "<=", val, self._table)
end

--- Greater than comparison (column > value)
--- @param value number|Jade.Value Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:gt(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, ">", val, self._table)
end

--- Greater than or equal (column >= value)
--- @param value number|Jade.Value Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:ge(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, ">=", val, self._table)
end

--- Not equal comparison (column != value)
--- @param value any Value to compare against
--- @return Jade.Condition WHERE condition object
function Expression:neq(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "!=", val, self._table)
end

--- LIKE pattern match (column LIKE value)
--- @param value string Pattern string
--- @return Jade.Condition WHERE condition object
function Expression:like(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "LIKE", value, self._table)
end

--- NOT LIKE pattern match (column NOT LIKE value)
--- @param value string Pattern string
--- @return Jade.Condition WHERE condition object
function Expression:notLike(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT LIKE", value, self._table)
end

--- Case-insensitive LIKE match (column ILIKE value) — PostgreSQL only
--- @param value string Pattern string
--- @return Jade.Condition WHERE condition object
function Expression:ilike(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "ILIKE", value, self._table)
end

--- IN list membership (column IN {values})
--- @param values table|any Array of values or single value
--- @return Jade.Condition WHERE condition object
function Expression:isIn(values)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IN", values, self._table)
end

--- NOT IN list exclusion (column NOT IN {values})
--- @param values table|any Array of values or single value
--- @return Jade.Condition WHERE condition object
function Expression:notIn(values)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT IN", values, self._table)
end

--- BETWEEN range check (column BETWEEN min AND max)
--- @param min any Lower bound
--- @param max any Upper bound
--- @return Jade.Condition WHERE condition object
function Expression:between(min, max)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "BETWEEN", {min, max}, self._table)
end

--- NOT BETWEEN range exclusion (column NOT BETWEEN min AND max)
--- @param min any Lower bound
--- @param max any Upper bound
--- @return Jade.Condition WHERE condition object
function Expression:notBetween(min, max)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT BETWEEN", {min, max}, self._table)
end

--- IS NULL test (column IS NULL)
--- @return Jade.Condition WHERE condition object
function Expression:isNull()
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IS", nil, self._table)
end

--- IS NOT NULL test (column IS NOT NULL)
--- @return Jade.Condition WHERE condition object
function Expression:isNotNull()
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IS NOT", nil, self._table)
end

--- Alias a column in SELECT output
--- @param alias string Column alias name
--- @return table Table with _alias field for SELECT rendering
function Expression:as(alias)
    return {
        _column = self._column,
        _table = self._table,
        _alias = alias,
    }
end

--- Raw SQL fragment — bypasses validation, use with caution
--- Validates against UNION injection and multi-statement attacks
--- @param sql string Raw SQL fragment (must not contain dangerous patterns)
--- @vararg any Bindings to append
--- @return Jade.RawExpression Object with compile() method
function Expression.raw(sql, ...)
    local bindings = { ... }

    -- Validate the raw SQL for obviously dangerous patterns
    if type(sql) ~= "string" then
        error("Expression.raw() requires a string SQL fragment")
    end
    local upper = sql:upper()
    -- Block multi-statement (semicolons)
    -- Allow semicolons inside string literals but not as statement separators
    if upper:match(";%s*[A-Z]") and not upper:match("';'.*;'") then
        -- Only block if semicolon is not inside a quoted string
        local stripped = sql:gsub("'[^']*'", ""):gsub('"[^"]*"', "")
        if stripped:match(";") then
            error("Expression.raw() does not allow multiple statements (contains ';')")
        end
    end
    -- Block UNION injection
    if upper:match("UNION%s+ALL%s+SELECT") or upper:match("UNION%s+SELECT") then
        error("Expression.raw() does not allow UNION SELECT")
    end

    local raw = {
        _raw = sql,
        _bindings = bindings,
    }
    function raw:compile(bindings_out)
        bindings_out = bindings_out or {}
        for _, v in ipairs(self._bindings) do
            bindings_out[#bindings_out + 1] = v
        end
        return self._raw, bindings_out
    end
    return raw
end

-- Load JSON extension — adds jsonContains, jsonExists, jsonPath methods
require("jade.query.expression-json")(Expression)

return Expression
