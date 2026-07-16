local M = {}

function M.setup(entity, options)
    options = options or {}
    local column = options.column or "deleted_at"
    local Query = require("jade.query")
    local Condition = require("jade.query.condition")
    local Instance = require("jade.entity.instance")

    -- Add deleted_at column to entity
    local Timestamp = require("jade.types.timestamp")
    entity._columns[column] = Timestamp():defaultNow()
    entity._columns[column]._name = column
    entity._columns[column]._table = entity._table

    -- Store soft delete config
    entity._soft_delete = {
        column = column,
    }

    -- Override create to strip deleted_at from inserts
    local original_create = entity.create
    entity.create = function(self, data)
        data[column] = nil
        return original_create(self, data)
    end

    -- Override delete to do soft delete
    local original_delete = entity.delete
    entity.delete = function(self, id)
        local data = {}
        data[column] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        return self:update(id, data)
    end

    -- Add soft delete methods
    function entity:forceDelete(id)
        local where = Condition.new("id", "=", id, self._table)
        local sql, bindings = self._driver:generateDelete(self._table, where)
        local result = self._driver:execute(sql, bindings)
        local row = result[1] or result
        return Instance.new(self, row)
    end

    function entity:withTrashed()
        return Query.new(self)
    end

    function entity:onlyTrashed()
        local where = Condition.new(column, "IS NOT", nil, self._table)
        return Query.new(self):where(where)
    end

    function entity:restore(id)
        local data = {}
        data[column] = nil
        local where = Condition.new("id", "=", id, self._table)
        local sql, bindings = self._driver:generateUpdate(self._table, data, where)
        return self._driver:execute(sql, bindings)
    end

    -- Override get to exclude soft-deleted rows by default
    entity.get = function(self)
        local where = Condition.new(column, "IS", nil, self._table)
        return Query.new(self):where(where):get()
    end

    return entity
end

function M.isSoftDeleted(entity)
    return entity._soft_delete ~= nil
end

function M.getSoftDeleteColumn(entity)
    if entity._soft_delete then
        return entity._soft_delete.column
    end
    return nil
end

return M