local M = {}

function M.setup(entity, options)
    options = options or {}
    local column = options.column or "deleted_at"
    local cascade = options.cascade ~= false -- default true
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
        cascade = cascade,
    }

    -- Override create to strip deleted_at from inserts
    local original_create = entity.create
    entity.create = function(self, data)
        data[column] = nil
        return original_create(self, data)
    end

    -- Helper to cascade soft delete to related entities
    local function cascadeSoftDelete(entity_instance, id)
        if not entity._relations then return end

        local now = os.date("!%Y-%m-%dT%H:%M:%SZ")

        for name, rel in pairs(entity._relations) do
            local target = rel.target
            if target and M.isSoftDeleted(target) then
                local target_column = M.getSoftDeleteColumn(target)
                local foreign_key = rel.foreign_key

                if rel.type == "hasMany" or rel.type == "hasOne" then
                    -- Update related entities
                    local data = {}
                    data[target_column] = now
                    local where = Condition.new(foreign_key, "=", id, target._table)
                    local sql, bindings = target._driver:generateUpdate(target._table, data, where)
                    target._driver:execute(sql, bindings)
                elseif rel.type == "hasAndBelongsToMany" then
                    -- Update join table
                    local join_data = {}
                    join_data[target_column] = now
                    local join_where = Condition.new(rel.source_foreign_key, "=", id, rel.join_table)
                    local join_sql, join_bindings = target._driver:generateUpdate(rel.join_table, join_data, join_where)
                    target._driver:execute(join_sql, join_bindings)
                end
            end
        end
    end

    -- Helper to cascade restore related entities
    local function cascadeRestore(entity_instance, id)
        if not entity._relations then return end

        for name, rel in pairs(entity._relations) do
            local target = rel.target
            if target and M.isSoftDeleted(target) then
                local target_column = M.getSoftDeleteColumn(target)
                local foreign_key = rel.foreign_key

                if rel.type == "hasMany" or rel.type == "hasOne" then
                    -- Restore related entities
                    local data = {}
                    data[target_column] = nil
                    local where = Condition.new(foreign_key, "=", id, target._table)
                    local sql, bindings = target._driver:generateUpdate(target._table, data, where)
                    target._driver:execute(sql, bindings)
                elseif rel.type == "hasAndBelongsToMany" then
                    -- Restore join table
                    local join_data = {}
                    join_data[target_column] = nil
                    local join_where = Condition.new(rel.source_foreign_key, "=", id, rel.join_table)
                    local join_sql, join_bindings = target._driver:generateUpdate(rel.join_table, join_data, join_where)
                    target._driver:execute(join_sql, join_bindings)
                end
            end
        end
    end

    -- Override delete to do soft delete with cascade
    local original_delete = entity.delete
    entity.delete = function(self, id)
        local data = {}
        data[column] = os.date("!%Y-%m-%dT%H:%M:%SZ")

        -- Cascade to related entities if enabled
        if cascade then
            cascadeSoftDelete(nil, id)
        end

        return self:update(id, data)
    end

    -- Add soft delete methods
    function entity:forceDelete(id)
        -- Force delete related entities if cascade
        if cascade and entity._relations then
            for name, rel in pairs(entity._relations) do
                local target = rel.target
                if target and M.isSoftDeleted(target) then
                    local foreign_key = rel.foreign_key
                    if rel.type == "hasMany" or rel.type == "hasOne" then
                        local where = Condition.new(foreign_key, "=", id, target._table)
                        local sql, bindings = target._driver:generateDelete(target._table, where)
                        target._driver:execute(sql, bindings)
                    end
                end
            end
        end

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

        -- Cascade restore to related entities if enabled
        if cascade then
            cascadeRestore(nil, id)
        end

        local where = Condition.new("id", "=", id, self._table)
        local sql, bindings = self._driver:generateUpdate(self._table, data, where)
        return self._driver:execute(sql, bindings)
    end

    -- Override get to exclude soft-deleted rows by default
    entity.get = function(self)
        local where = Condition.new(column, "IS", nil, self._table)
        return Query.new(self):where(where):get()
    end

    -- Add scope methods for queries
    function entity:withoutTrashed()
        local where = Condition.new(column, "IS", nil, self._table)
        return Query.new(self):where(where)
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

function M.hasCascade(entity)
    if entity._soft_delete then
        return entity._soft_delete.cascade
    end
    return false
end

return M
