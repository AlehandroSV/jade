--- Jade Plugin: Callbacks
--- Wraps entity/callbacks.lua as a pluggable lifecycle hook system.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.callbacks"))
---
--- Note: The existing Callbacks module is already integrated into Entity.new().
--- This plugin makes it opt-in and allows external hooks via the hook registry.

local BaseCallbacks = require("jade.entity.callbacks")

local M = {}

M.name        = "callbacks"
M.version     = "1.0.0"
M.description = "Lifecycle callbacks (before/after/around) for CRUD operations"

-- Extend hooks fire during entity construction
M.hooks = {
    extendEntity = function(context_)
        -- Wrap the entity with callback methods
        -- We check _callbacks to avoid double-setup since Entity.new() already calls this
        if not context_.entity._callbacks or next(context_.entity._callbacks) == nil then
            BaseCallbacks.setup(context_.entity)
        end
    end,
}

--- Install callbacks globally on all entities.
--- @param jade table The plugin API instance
--- @param options table|nil Options: currently none reserved
--- @return boolean ok
function M.setup(jade, options)
    return true
end

function M.teardown(jade)
    -- No state to clean up; callbacks are per-entity.
end

return M
