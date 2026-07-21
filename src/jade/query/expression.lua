local Expression = {}
Expression.__index = Expression

function Expression.new(column_name, table_name)
    return setmetatable({
        _column = column_name,
        _table = table_name,
    }, Expression)
end

function Expression:eq(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "=", val, self._table)
end

function Expression:lt(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "<", val, self._table)
end

function Expression:le(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "<=", val, self._table)
end

function Expression:gt(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, ">", val, self._table)
end

function Expression:ge(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, ">=", val, self._table)
end

function Expression:neq(value)
    local Condition = require("jade.query.condition")
    local val = type(value) == "table" and value._value or value
    return Condition.new(self._column, "!=", val, self._table)
end

function Expression:like(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "LIKE", value, self._table)
end

function Expression:notLike(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT LIKE", value, self._table)
end

function Expression:ilike(value)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "ILIKE", value, self._table)
end

function Expression:isIn(values)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IN", values, self._table)
end

function Expression:notIn(values)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT IN", values, self._table)
end

function Expression:between(min, max)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "BETWEEN", {min, max}, self._table)
end

function Expression:notBetween(min, max)
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "NOT BETWEEN", {min, max}, self._table)
end

function Expression:isNull()
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IS", nil, self._table)
end

function Expression:isNotNull()
    local Condition = require("jade.query.condition")
    return Condition.new(self._column, "IS NOT", nil, self._table)
end

function Expression:as(alias)
    return {
        _column = self._column,
        _table = self._table,
        _alias = alias,
    }
end

function Expression.raw(sql, ...)
    local bindings = { ... }

    -- Validate the raw SQL for obviously dangerous patterns
    if type(sql) ~= "string" then
        error("Expression.raw() requires a string SQL fragment")
    end
    local upper = sql:upper()
    -- Block multi-statement (semicolons)
    -- Allow semicolons inside string literals but not as statement separators
    if sql:match(";%s*[A-Z]") and not sql:match("';'.*;'") then
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

return Expression