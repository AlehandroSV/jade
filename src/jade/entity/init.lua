local Expression = require("jade.query.expression")
local Query = require("jade.query")
local Instance = require("jade.entity.instance")
local Relations = require("jade.entity.relations")
local Validations = require("jade.entity.validations")
local Callbacks = require("jade.entity.callbacks")

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
        _validations = {},
        _callbacks = {},
        _scopes = {},
    }, Entity)

    -- Register column names
    for name, col in pairs(columns) do
        col._name = name
        col._table = table_name
    end

    -- Setup validations and callbacks
    Validations.setup(model)
    Callbacks.setup(model)

    return model
end

function Entity:configure(driver)
    self._driver = driver
end

function Entity:scope(name, ...)
    local args = { ... }
    if #args > 0 and type(args[1]) == "function" then
        -- Define scope
        self._scopes[name] = args[1]
        return self
    else
        -- Invoke scope
        local scope_fn = self._scopes[name]
        if scope_fn then
            local q = Query.new(self)
            return scope_fn(q, unpack(args))
        end
        return Query.new(self)
    end
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

function Entity:hasAndBelongsToMany(target_entity, options)
    local relation = Relations.hasAndBelongsToMany(self, target_entity, options)
    local name = target_entity._table
    self._relations[name] = relation
    return self
end

function Entity:hasManyThrough(target_entity, through_entity, options)
    local relation = Relations.hasManyThrough(self, target_entity, through_entity, options)
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

function Entity:distinct()
    return Query.new(self):distinct()
end

function Entity:join(table_name, on_condition)
    return Query.new(self):join(table_name, on_condition)
end

function Entity:leftJoin(table_name, on_condition)
    return Query.new(self):leftJoin(table_name, on_condition)
end

function Entity:groupBy(...)
    return Query.new(self):groupBy(...)
end

function Entity:having(condition)
    return Query.new(self):having(condition)
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

function Entity:min(column)
    return Query.new(self):min(column)
end

function Entity:max(column)
    return Query.new(self):max(column)
end

function Entity:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(Query.new(self), options)
end

function Entity:exists()
    return Query.new(self):exists()
end

function Entity:empty()
    return Query.new(self):empty()
end

function Entity:pluck(column)
    return Query.new(self):pluck(column)
end

function Entity:take(n)
    return Query.new(self):take(n)
end

function Entity:inBatches(batchSize, fn)
    return Query.new(self):inBatches(batchSize, fn)
end

-- CRUD with validation and callbacks
function Entity:create(data)
    -- Run validations
    local errors = self:validate(data)
    if errors then
        error("Validation failed: " .. table.concat(errors, ", "))
    end

    -- Run around callbacks
    local result = Callbacks.runAround(self, "around_save", nil, data, function()
        Callbacks.run(self, "before_save", nil, data)
        Callbacks.run(self, "before_create", nil, data)

        local sql, bindings = self._driver:generateInsert(self._table, data, self)
        local result = self._driver:execute(sql, bindings)
        local row = result[1] or result
        local instance = Instance.new(self, row)

        Callbacks.run(self, "after_create", instance, data)
        Callbacks.run(self, "after_save", instance, data)

        return instance
    end)

    return result
end

function Entity:update(id, data)
    -- Run validations
    data.id = id
    local errors = self:validate(data)
    if errors then
        error("Validation failed: " .. table.concat(errors, ", "))
    end

    -- Run around callbacks
    local result = Callbacks.runAround(self, "around_save", nil, data, function()
        Callbacks.run(self, "before_save", nil, data)
        Callbacks.run(self, "before_update", nil, data)

        local Condition = require("jade.query.condition")
        local where = Condition.new("id", "=", id, self._table)
        local sql, bindings = self._driver:generateUpdate(self._table, data, where)
        local result = self._driver:execute(sql, bindings)
        local row = result[1] or result
        local instance = Instance.new(self, row)

        Callbacks.run(self, "after_update", instance, data)
        Callbacks.run(self, "after_save", instance, data)

        return instance
    end)

    return result
end

function Entity:delete(id)
    -- Run callbacks
    Callbacks.run(self, "before_delete", nil, { id = id })

    local Condition = require("jade.query.condition")
    local where = Condition.new("id", "=", id, self._table)
    local sql, bindings = self._driver:generateDelete(self._table, where)
    local result = self._driver:execute(sql, bindings)
    local row = result[1] or result
    local instance = Instance.new(self, row)

    Callbacks.run(self, "after_delete", instance, { id = id })

    return instance
end

return Entity