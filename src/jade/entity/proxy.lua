local JadeErrors = require("jade.errors")

local Proxy = {}
Proxy.__index = function(self, key)
    local data = rawget(self, "_data")
    if data and data[key] ~= nil then
        return data[key]
    end

    local method = rawget(Proxy, key)
    if method then
        return method
    end

    return nil
end

function Proxy.new(relation, owner)
    return setmetatable({
        _relation = relation,
        _owner = owner,
        _data = nil,
        _loaded = false,
    }, Proxy)
end

function Proxy:load()
    if self._loaded then
        return self._data
    end

    local relation = self._relation
    local target = relation.target
    local driver = target._driver

    if not driver then
        JadeErrors.raise(JadeErrors.CONFIG_MISSING, {
            path = "driver",
        }, 2)
    end

    local value
    if relation.type == "belongsTo" then
        -- owner has foreign_key, load target by that key
        local foreign_key_value = self._owner[relation.foreign_key]
        if foreign_key_value then
            value = target:find(foreign_key_value)
        end
    elseif relation.type == "hasOne" then
        -- target has foreign_key pointing to owner
        local Condition = require("jade.query.condition")
        local where = Condition.new(relation.foreign_key, "=", self._owner.id, target._table)
        local results = target:where(where):limit(1):get()
        value = results[1]
    elseif relation.type == "hasMany" then
        local Condition = require("jade.query.condition")
        local where = Condition.new(relation.foreign_key, "=", self._owner.id, target._table)
        value = target:where(where):get()
    elseif relation.type == "foreign_key" then
        -- owner has foreign_key, load target
        local foreign_key_value = self._owner[relation.foreign_key]
        if foreign_key_value then
            value = target:find(foreign_key_value)
        end
    end

    self._data = value
    self._loaded = true
    return value
end

function Proxy:isLoaded()
    return self._loaded
end

function Proxy:getData()
    if not self._loaded then
        self:load()
    end
    return self._data
end

-- Create a related record and link it
function Proxy:create(data)
    local relation = self._relation
    local target = relation.target
    local owner = self._owner

    if relation.type == "belongsTo" then
        -- Create target, set FK on owner
        local record = target:create(data)
        owner:update({ [relation.foreign_key] = record._data.id })
        self._data = record
        self._loaded = true
        return record

    elseif relation.type == "hasOne" then
        -- Create target with FK pointing to owner
        data[relation.foreign_key] = owner.id
        local record = target:create(data)
        self._data = record
        self._loaded = true
        return record

    elseif relation.type == "hasMany" then
        -- Create target with FK pointing to owner
        data[relation.foreign_key] = owner.id
        local record = target:create(data)
        -- Invalidate cache so next load() picks it up
        self._loaded = false
        self._data = nil
        return record

    elseif relation.type == "hasAndBelongsToMany" then
        -- Create target and insert into pivot table
        local record = target:create(data)
        local driver = owner._driver
        driver:execute(
            string.format("INSERT INTO %s (%s, %s) VALUES ($1, $2)",
                relation.join_table, relation.source_foreign_key, relation.target_foreign_key),
            { owner.id, record._data.id }
        )
        self._loaded = false
        self._data = nil
        return record
    end
end

-- Connect an existing record
function Proxy:connect(id_or_where)
    local relation = self._relation
    local target = relation.target
    local owner = self._owner

    local record
    if type(id_or_where) == "number" then
        record = target:find(id_or_where)
    else
        record = target:findUnique({ where = id_or_where })
    end

    if not record then
        JadeErrors.raise(JadeErrors.NO_ROWS_FOUND, {
            table = target._table,
        }, 2)
    end

    if relation.type == "belongsTo" then
        owner:update({ [relation.foreign_key] = record._data.id })
        self._data = record
        self._loaded = true

    elseif relation.type == "hasOne" or relation.type == "hasMany" then
        record:update({ [relation.foreign_key] = owner.id })
        self._loaded = false
        self._data = nil

    elseif relation.type == "hasAndBelongsToMany" then
        local driver = owner._driver
        driver:execute(
            string.format("INSERT INTO %s (%s, %s) VALUES ($1, $2)",
                relation.join_table, relation.source_foreign_key, relation.target_foreign_key),
            { owner.id, record._data.id }
        )
        self._loaded = false
        self._data = nil
    end

    return record
end

-- Disconnect a related record
function Proxy:disconnect(id_or_where)
    local relation = self._relation
    local target = relation.target
    local owner = self._owner

    if relation.type == "belongsTo" then
        owner:update({ [relation.foreign_key] = nil })
        self._data = nil
        self._loaded = true

    elseif relation.type == "hasOne" or relation.type == "hasMany" then
        local record
        if type(id_or_where) == "number" then
            record = target:find(id_or_where)
        else
            record = target:findUnique({ where = id_or_where })
        end
        if record then
            record:update({ [relation.foreign_key] = nil })
        end
        self._loaded = false
        self._data = nil

    elseif relation.type == "hasAndBelongsToMany" then
        local record
        if type(id_or_where) == "number" then
            record = target:find(id_or_where)
        else
            record = target:findUnique({ where = id_or_where })
        end
        if record then
            local driver = owner._driver
            driver:execute(
                string.format("DELETE FROM %s WHERE %s = $1 AND %s = $2",
                    relation.join_table, relation.source_foreign_key, relation.target_foreign_key),
                { owner.id, record._data.id }
            )
        end
        self._loaded = false
        self._data = nil
    end
end

return Proxy
