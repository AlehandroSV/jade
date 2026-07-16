local Condition = {}
Condition.__index = Condition

function Condition.new(column, op, value, table_name)
    local self = {
        column = column,
        op = op,
        value = value,
        table_name = table_name,
        type = "simple",
    }
    setmetatable(self, Condition)
    return self
end

function Condition:band(other)
    local self = {
        left = self,
        right = other,
        type = "and",
    }
    setmetatable(self, Condition)
    return self
end

function Condition:bor(other)
    local self = {
        left = self,
        right = other,
        type = "or",
    }
    setmetatable(self, Condition)
    return self
end

function Condition:compile(bindings)
    bindings = bindings or {}

    if self.type == "and" then
        local left_sql, left_bindings = self.left:compile({})
        local right_sql, right_bindings = self.right:compile({})
        local result = "(" .. left_sql .. " AND " .. right_sql .. ")"
        for _, v in ipairs(left_bindings) do
            bindings[#bindings + 1] = v
        end
        for _, v in ipairs(right_bindings) do
            bindings[#bindings + 1] = v
        end
        return result, bindings
    end

    if self.type == "or" then
        local left_sql, left_bindings = self.left:compile({})
        local right_sql, right_bindings = self.right:compile({})
        local result = "(" .. left_sql .. " OR " .. right_sql .. ")"
        for _, v in ipairs(left_bindings) do
            bindings[#bindings + 1] = v
        end
        for _, v in ipairs(right_bindings) do
            bindings[#bindings + 1] = v
        end
        return result, bindings
    end

    local col_ref
    if self.table_name and self.table_name ~= "" then
        col_ref = self.table_name .. "." .. self.column
    else
        col_ref = self.column
    end

    -- Special handling for IS NULL / IS NOT NULL
    if self.op == "IS" or self.op == "IS NOT" then
        return col_ref .. " " .. self.op .. " NULL", bindings
    end

    bindings[#bindings + 1] = self.value
    return col_ref .. " " .. self.op .. " ?", bindings
end

return Condition
