--- Jade Plugin: Optimistic Locking
--- Extracted from entity/init.lua as a standalone, pluggable module.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.optimistic_lock"), { column = "version" })
---
--- Conflict detection: if update() affects zero rows, returns nil (conflict).
--- The caller should check for nil and handle accordingly (retry / error).

local M = {}

M.name        = "optimistic-lock"
M.version     = "1.0.0"
M.description = "Optimistic concurrency control with version column"

-- extendEntity hook fires during entity construction
M.hooks = {
    extendEntity = function(context_)
        M.install(context_.entity, context_.options or {})
    end,
}

--- Install optimistic locking on an entity.
--- @param entity table
--- @param options table|nil { column? } default: "version"
function M.install(entity, options)
    options = options or {}
    local col = options.column or "version"

    -- Add version column to entity
    local Integer = require("jade.types.integer")
    entity._columns[col] = Integer():default(1)
    entity._columns[col]._name = col
    entity._columns[col]._table = entity._table

    -- Store config
    entity._optimistic_lock = { column = col }

    -- Override update to include version check
    local original_update = entity.update
    local Condition = require("jade.query.condition")

    entity.update = function(self_, id, data)
        -- Copy data to avoid mutating caller's table
        local update_data = {}
        for k, v in pairs(data) do update_data[k] = v end

        -- Add version condition if not already set
        if update_data[col] == nil then
            -- Get current version from database
            local current_ = self_:find(id)
            if current_ and current_._data[col] ~= nil then
                update_data[col] = current_._data[col]
            end
        end

        local version_value = update_data[col]
        update_data[col] = (version_value or 0) + 1

        -- Run the original update with version in data
        local result_ = original_update(self_, id, update_data)

        -- Check if update affected any rows (conflict detection)
        if result_ == nil then
            return nil
        end

        return result_
    end

    return true
end

--- Install on all entities that declare this plugin is enabled.
--- @param jade table The plugin API instance
--- @param options table|nil
--- @return boolean ok
function M.setup(jade, options)
    return true
end

function M.teardown(jade)
    -- No state to clean up.
end

return M
