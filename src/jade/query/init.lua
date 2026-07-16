local Expression = require("jade.query.expression")
local Condition = require("jade.query.condition")
local Instance = require("jade.entity.instance")

local Query = {}
Query.__index = Query

function Query.new(entity)
    return setmetatable({
        _entity = entity,
        _table = entity._table,
        _where = {},
        _orderBy = {},
        _limit = nil,
        _offset = nil,
        _select = {},
        _includes = {},
        _bindings = {},
    }, Query)
end

function Query:where(condition)
    self._where[#self._where + 1] = condition
    return self
end

function Query:orderBy(column, direction)
    local col_name = column
    local dir = direction or "ASC"

    if type(column) == "table" and column._column then
        col_name = column._column
    end

    self._orderBy[#self._orderBy + 1] = { column = col_name, dir = dir }
    return self
end

function Query:limit(n)
    self._limit = n
    return self
end

function Query:offset(n)
    self._offset = n
    return self
end

function Query:select(...)
    local cols = { ... }
    if #cols == 1 and type(cols[1]) == "table" then
        cols = cols[1]
    end
    for _, col in ipairs(cols) do
        self._select[#self._select + 1] = col
    end
    return self
end

function Query:include(relation_name)
    self._includes[#self._includes + 1] = relation_name
    return self
end

function Query:get()
    local sql, bindings = self:toSQL()
    local driver = self._entity._driver
    local raw = driver:execute(sql, bindings)
    local instances = {}
    for i, row in ipairs(raw) do
        instances[i] = Instance.new(self._entity, row)
    end
    return instances
end

function Query:first()
    self._limit = 1
    local results = self:get()
    return results[1]
end

function Query:find(id)
    self._where = {}
    self._where[1] = Condition.new("id", "=", id, self._table)
    self._limit = 1
    local results = self:get()
    return results[1]
end

function Query:count()
    self._select = { "COUNT(*) as count" }
    local sql, bindings = self:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].count or 0
end

function Query:sum(column)
    self._select = { "SUM(" .. column .. ") as sum" }
    local sql, bindings = self:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].sum or 0
end

function Query:average(column)
    self._select = { "AVG(" .. column .. ") as avg" }
    local sql, bindings = self:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].avg or 0
end

function Query:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(self, options)
end

function Query:toSQL()
    local driver = self._entity._driver
    return driver:generateSelect(self)
end

return Query
