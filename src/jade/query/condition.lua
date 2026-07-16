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
    local composite = {
        left = self,
        right = other,
        type = "and",
    }
    setmetatable(composite, Condition)
    return composite
end

function Condition:bor(other)
    local composite = {
        left = self,
        right = other,
        type = "or",
    }
    setmetatable(composite, Condition)
    return composite
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

    -- Special handling for IN clause
    if self.op == "IN" then
        local placeholders = {}
        for i = 1, #self.value do
            placeholders[i] = "?"
            bindings[#bindings + 1] = self.value[i]
        end
        return col_ref .. " IN (" .. table.concat(placeholders, ", ") .. ")", bindings
    end

    -- Special handling for NOT IN clause
    if self.op == "NOT IN" then
        local placeholders = {}
        for i = 1, #self.value do
            placeholders[i] = "?"
            bindings[#bindings + 1] = self.value[i]
        end
        return col_ref .. " NOT IN (" .. table.concat(placeholders, ", ") .. ")", bindings
    end

    -- Special handling for BETWEEN
    if self.op == "BETWEEN" then
        bindings[#bindings + 1] = self.value[1]
        bindings[#bindings + 1] = self.value[2]
        return col_ref .. " BETWEEN ? AND ?", bindings
    end

    -- Special handling for NOT BETWEEN
    if self.op == "NOT BETWEEN" then
        bindings[#bindings + 1] = self.value[1]
        bindings[#bindings + 1] = self.value[2]
        return col_ref .. " NOT BETWEEN ? AND ?", bindings
    end

    bindings[#bindings + 1] = self.value
    return col_ref .. " " .. self.op .. " ?", bindings
end

return Condition