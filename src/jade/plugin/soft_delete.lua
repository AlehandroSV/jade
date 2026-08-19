--- Jade Plugin: Soft Delete
--- Wraps entity/soft_delete.lua as a pluggable module.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.soft_delete"), { column = "deleted_at", cascade = true })

local BaseSoftDelete = require("jade.entity.soft_delete")

local M = {}

M.name        = "soft-delete"
M.version     = "1.0.0"
M.description = "Soft delete support with cascade and restore"

-- Hook registration: soft delete modifies query builders via :withTrashed(), :onlyTrashed()
-- This is mostly done at entity level, so we provide extendEntity hook.
M.hooks = {
    -- Extend entity to support soft delete methods
    extendEntity = function(context_)
        local entity = context_.entity
        if entity._columns and BaseSoftDelete.isSoftDeleted(entity) then
            -- Already set up by setup() — skip duplicate install
            return
        end
        BaseSoftDelete.setup(entity, context_.options or {})
    end,
}

--- Install soft delete on all entities that declare it.
--- @param jade table The plugin API instance
--- @param options table|nil Options: { column?, cascade? }
--- @return boolean ok
--- @return string|nil error
function M.setup(jade, options)
    -- No global setup needed; soft delete is applied per-entity
    -- via extendEntity hook when entity is instantiated.
    -- The column constraint handler will add deleted_at as needed.
    return true
end

function M.teardown(jade)
    -- Soft delete doesn't hold resources; nothing to clean up.
end

return M
