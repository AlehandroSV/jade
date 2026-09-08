--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief Instance class representing a single database record

--- @class Jade.Instance : table
--- @field _entity Jade.Entity The entity this instance belongs to
--- @field _data table<string, any> Raw record data
local Instance = {}
Instance.__index = function(self, key)
    local method = rawget(Instance, key)
    if method then
        return method
    end

    -- Access data fields
    if self._data and self._data[key] ~= nil then
        return self._data[key]
    end

    return nil
end

--- Create a new Instance
--- @param entity Jade.Entity Entity definition
--- @param data table<string, any> Record data
--- @return Jade.Instance New instance
function Instance.new(entity, data)
    return setmetatable({
        _entity = entity,
        _data = data or {},
    }, Instance)
end

--- Update instance fields and persist to database
--- @param data table<string, any> Fields to update
--- @return Jade.Instance self
function Instance:update(data)
    local id = self._data.id
    if not id then
        error("Cannot update instance without id")
    end

    -- Pass version from instance data for optimistic locking
    if self._entity._optimistic_locking then
        local version_col = self._entity._optimistic_locking.column
        if data[version_col] == nil and self._data[version_col] ~= nil then
            data[version_col] = self._data[version_col]
        end
    end

    local result = self._entity:update(id, data)
    if result == nil then
        return nil
    end
    -- Only copy column data (skip relation instructions)
    for k, v in pairs(data) do
        if self._entity._columns[k] then
            self._data[k] = v
        end
    end
    -- Refresh resolved FK values from result
    if result._data then
        for k, v in pairs(result._data) do
            self._data[k] = v
        end
    end
    return self
end

--- Delete this record from the database
--- @return Jade.Instance self
function Instance:delete()
    local id = self._data.id
    if not id then
        error("Cannot delete instance without id")
    end
    return self._entity:delete(id)
end

--- Save the instance (create if new, update if existing)
--- @return Jade.Instance self
function Instance:save()
    if self._data.id then
        return self:update(self._data)
    else
        local result = self._entity:create(self._data)
        self._data = result._data
        return self
    end
end

--- Reload instance data from database
--- @return Jade.Instance self
function Instance:refresh()
    local id = self._data.id
    if not id then
        error("Cannot refresh instance without id")
    end
    local fresh = self._entity:find(id)
    if fresh then
        self._data = fresh._data
    end
    return self
end

--- Convert instance to plain table
--- @return table<string, any> Record data as plain table
function Instance:toTable()
    local copy = {}
    for k, v in pairs(self._data) do
        copy[k] = v
    end
    return copy
end

return Instance
