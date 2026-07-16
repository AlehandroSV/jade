local Expression = require("jade.query.expression")
local Query = require("jade.query")
local Instance = require("jade.entity.instance")
local Relations = require("jade.entity.relations")

local Entity = {}
Entity.__index = function(self, key)
    -- Check if key is a method
    local method = rawget(Entity, key)
    if method then
        return method
    end

    -- Check if key is a relation -> return lazy proxy
    if self._relations and self._relations[key] then
        local Proxy = require("jade.entity.proxy")
        return Proxy.new(self._relations[key], self._owner or self)
    end

    -- Check if key is a column name -> return Expression
    if self._columns and self._columns[key] then
        return Expression.new(key, self._table)
    end

    return nil
end

function Entity.new(table_name, columns)
    local model = setmetatable({
        _table = table_name,
        _columns = columns,
        _relations = {},
        _driver = nil,
    }, Entity)

    -- Register column names
    for name, col in pairs(columns) do
        col._name = name
        col._table = table_name
    end

    return model
end

function Entity:configure(driver)
    self._driver = driver
end

-- Relation definitions
function Entity:belongsTo(target_entity, options)
    local relation = Relations.belongsTo(target_entity, options)
    local name = target_entity._table
    self._relations[name] = relation
    return self
end

function Entity:hasOne(target_entity, options)
    local relation = Relations.hasOne(self, target_entity, options)
    local name = target_entity._table
    self._relations[name] = relation
    return self
end

function Entity:hasMany(target_entity, options)
    local relation = Relations.hasMany(self, target_entity, options)
    local name = target_entity._table
    self._relations[name] = relation
    return self
end

function Entity:foreignKey(target_entity, options)
    local relation = Relations.ForeignKey(target_entity, options)
    local name = target_entity._table
    self._relations[name] = relation
    return self
end

-- Query methods
function Entity:where(condition)
    return Query.new(self):where(condition)
end

function Entity:orderBy(column, direction)
    return Query.new(self):orderBy(column, direction)
end

function Entity:limit(n)
    return Query.new(self):limit(n)
end

function Entity:offset(n)
    return Query.new(self):offset(n)
end

function Entity:select(...)
    return Query.new(self):select(...)
end

function Entity:include(relation_name)
    return Query.new(self):include(relation_name)
end

function Entity:get()
    return Query.new(self):get()
end

function Entity:first()
    return Query.new(self):first()
end

function Entity:find(id)
    return Query.new(self):find(id)
end

function Entity:count()
    return Query.new(self):count()
end

function Entity:sum(column)
    return Query.new(self):sum(column)
end

function Entity:average(column)
    return Query.new(self):average(column)
end

function Entity:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(Query.new(self), options)
end

-- CRUD
function Entity:create(data)
    local sql, bindings = self._driver:generateInsert(self._table, data, self)
    local result = self._driver:execute(sql, bindings)
    local row = result[1] or result
    return Instance.new(self, row)
end

function Entity:update(id, data)
    local Condition = require("jade.query.condition")
    local where = Condition.new("id", "=", id, self._table)
    local sql, bindings = self._driver:generateUpdate(self._table, data, where)
    local result = self._driver:execute(sql, bindings)
    local row = result[1] or result
    return Instance.new(self, row)
end

function Entity:delete(id)
    local Condition = require("jade.query.condition")
    local where = Condition.new("id", "=", id, self._table)
    local sql, bindings = self._driver:generateDelete(self._table, where)
    local result = self._driver:execute(sql, bindings)
    local row = result[1] or result
    return Instance.new(self, row)
end

return Entity
