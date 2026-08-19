--- Hook lifecycle registry for the Jade plugin system.
---
--- Hook types and when they fire:
---
--- Query hooks (on Query builder instances):
---   beforeQuery  —  right before SQL is generated and executed
---   afterQuery   —  immediately after query results are returned
---
--- Connection hooks (on driver level):
---   beforeConnect —  before a new database connection is established
---   afterConnect  —  after the connection is successfully opened
---
--- CRUD hooks (on Entity instances, via Callbacks compatibility shim):
---   create / update / delete / save  — each has "before" and "after" variants
---   around_*  variants for wrapping logic (chained)
---
--- Extension hooks:
---   extendEntity(entity, jade, pluginName)  — called after entity setup, lets plugin add methods/columns
---   extendQuery(query, jade, pluginName)    — called after query builder init
---   extendDriver(driver, jade, pluginName)  — called after driver creation

local M = {}

-- Registry of hook handlers, structured as:
-- hooks[hook_type][plugin_name] = { handler1, handler2, ... }
local hooks = {}

-- Global extension hooks that apply to ALL entities/queries/drivers
-- These run BEFORE per-entity hooks so plugins can still override defaults.
local globalExtendEntity   = {}
local globalExtendQuery    = {}
local globalExtendDriver   = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

local function ensure(type_, name_)
    if not hooks[type_] then
        hooks[type_] = {}
    end
    if not hooks[type_][name_] then
        hooks[type_][name_] = {}
    end
    return hooks[type_][name_]
end

---------------------------------------------------------------------------
-- Registration API
---------------------------------------------------------------------------

--- Register a handler function for a specific hook.
--- @param hook_type string One of: beforeQuery, afterQuery, beforeConnect, afterConnect,
---          beforeCreate, afterCreate, beforeUpdate, afterUpdate, beforeDelete, afterDelete,
---          beforeSave, afterSave, extendEntity, extendQuery, extendDriver
--- @param handler function The callback function
--- @param options table|nil Options: { plugin? (string, default "unknown"), entity? (table|nil), priority? (number) }
--- @return function handler The registered handler (for unregistration)
function M.register(hook_type, handler, options)
    if not options then options = {} end

    local source = options.plugin or "global"

    -- Extend hooks are special: they go into global arrays or per-plugin tables
    if hook_type == "extendEntity" then
        if not globalExtendEntity[source] then
            globalExtendEntity[source] = {}
        end
        table.insert(globalExtendEntity[source], handler)
        return handler
    end

    if hook_type == "extendQuery" then
        if not globalExtendQuery[source] then
            globalExtendQuery[source] = {}
        end
        table.insert(globalExtendQuery[source], handler)
        return handler
    end

    if hook_type == "extendDriver" then
        if not globalExtendDriver[source] then
            globalExtendDriver[source] = {}
        end
        table.insert(globalExtendDriver[source], handler)
        return handler
    end

    -- Regular hooks: organized by type → source
    local targets = ensure(hook_type, source)
    table.insert(targets, handler)
    return handler
end

--- Register all hooks defined by a plugin in one call.
--- Plugin.hooks should be:
---   {
---     beforeQuery  = { fn1, fn2 },
---     afterCreate  = { fn3 },
---     extendEntity = { fn4 },
---   }
--- @param plugin_name string
--- @param hooks_table table Mapping of hook_type -> array of handler functions
function M.registerPlugin(plugin_name, hooks_table)
    for hook_type, handlers in pairs(hooks_table) do
        if type(handlers) == "table" then
            for _, handler in ipairs(handlers) do
                M.register(hook_type, handler, { plugin = plugin_name })
            end
        elseif type(handlers) == "function" then
            M.register(hook_type, handlers, { plugin = plugin_name })
        end
    end
end

---------------------------------------------------------------------------
-- Firing API
---------------------------------------------------------------------------

--- Fire all handlers for a given hook type.
--- For non-extend hooks, also fires entity-scoped handlers if provided.
--- @param hook_type string The hook to fire
--- @param context table|nil Context data passed to each handler
--- @param entity table|nil Entity instance (for entity-scoped hooks like beforeCreate)
--- @return table results Array of { ok, result/error } for each handler
function M.fire(hook_type, context, entity)
    context = context or {}
    entity = entity or nil

    local all_results = {}

    --- Execute a flat array of handler functions
    --- @param handlers table Array of handler functions
    --- @param label string|nil Label for this batch
    local function execFlat(handlers, label_)
        if not handlers or #handlers == 0 then return end
        for idx_, handler_ in ipairs(handlers) do
            local ok_, result_ = pcall(handler_, context)
            all_results[#all_results + 1] = { ok = ok_, result = result_, source = label_ }
            if not ok_ then
                -- Stop on error for safety; report which hook failed
                return true -- signal early exit
            end
        end
        return false
    end

    --- Gather handlers from all sources into a single flat array
    --- @param sources_table table Nested table mapping source_name -> [handler, ...]
    --- @return table flat_array Combined flat array of all handlers
    local function flattenSources(sources_table_)
        local flat = {}
        if not sources_table_ then return flat end
        for _, handlers_list_ in pairs(sources_table_) do
            if type(handlers_list_) == "table" then
                for _, h_ in ipairs(handlers_list_) do
                    flat[#flat + 1] = h_
                end
            end
        end
        return flat
    end

    -- Order matters:
    -- 1. Global extend hooks (run first, plugins can override defaults)
    -- 2. Per-entity hooks (if entity provided)
    -- 3. Remaining global hooks

    if hook_type:match("^extend") then
        -- Extend hooks: fire per-entity first, then global overrides
        local entity_hooks_ = (entity and entity._plugin_extend_hooks) or {}
        if next(entity_hooks_) then
            execFlat(entity_hooks_, entity.name)
        end
        local global_list = rawget(M, "_globalExtend_" .. hook_type)
            or ({ extendEntity = globalExtendEntity, extendQuery = globalExtendQuery, extendDriver = globalExtendDriver })[hook_type]
        execFlat(flattenSources(global_list), "global")
    else
        -- Non-extend: fire per-entity first, then global
        local entity_scoped_ = (entity and entity._plugin_hooks) or {}
        if next(entity_scoped_) then
            execFlat(entity_scoped_, entity._table .. ".hooks")
        end
        local hook_sources = hooks[hook_type] or {}
        execFlat(flattenSources(hook_sources), "global")
    end

    return all_results
end

--- Fire CRUD-specific hooks with full context (instance, data).
--- This bridges the gap between the simple hook system and the existing
--- Callbacks module which operates per-entity per-method.
--- @param entity table
--- @param method string "create", "update", "delete", "save"
--- @param event string "before" | "after"
--- @param instance table|nil The entity instance being modified
--- @param data table|nil Data being operated on
function M.fireCRUD(entity, method, event, instance, data)
    local hook_type = event .. method -- e.g., "beforeCreate", "afterUpdate"
    local context_ = {
        entity = entity,
        method = method,
        event = event,
        instance = instance,
        data = data or {},
    }
    return M.fire(hook_type, context_, entity)
end

--- Fire around hooks for a given entity and method.
--- Similar to Callbacks.runAround() but uses the plugin hook registry.
--- @param entity table
--- @param method string
--- @param fn function The core operation to wrap
--- @return any result
function M.fireAround(entity, method, fn)
    local hook_type = "around" .. method
    local handlers_ = hooks[hook_type] and hooks[hook_type]["" ] and hooks[hook_type][""]

    if not handlers_ or #handlers_ == 0 then
        return fn()
    end

    -- Build chained around-callback execution
    local function execute_chain(idx_)
        if idx_ > #handlers_ then
            return fn()
        end
        local ok, result_ = pcall(handlers_[idx_], {
            entity = entity,
            next = function() return execute_chain(idx_ + 1) end,
        })
        if not ok then
            error("Plugin around hook (" .. method .. ", #" .. idx_ .. ") failed: " .. tostring(result_))
        end
        return result_
    end

    return execute_chain(1)
end

---------------------------------------------------------------------------
-- Teardown & cleanup
---------------------------------------------------------------------------

--- Remove all hooks for a given plugin. Called during teardown.
--- @param plugin_name string
function M.unregister(plugin_name)
    if plugin_name == "global" or plugin_name == "" then
        hooks = {}
        globalExtendEntity = {}
        globalExtendQuery = {}
        globalExtendDriver = {}
        return
    end

    hooks[plugin_name] = nil

    globalExtendEntity[plugin_name] = nil
    globalExtendQuery[plugin_name] = nil
    globalExtendDriver[plugin_name] = nil
end

--- Clear all hooks (mainly for testing).
function M.clear()
    hooks = {}
    globalExtendEntity = {}
    globalExtendQuery = {}
    globalExtendDriver = {}
end

---------------------------------------------------------------------------
-- Query & Driver convenience wrappers
---------------------------------------------------------------------------

--- Decorate a driver's execute method with beforeQuery/afterQuery hooks.
--- Automatically installed when a plugin registers those hooks.
--- @param driver table The driver object
--- @param jade table The Jade config
--- @return table original_driver Reference to the decorated driver
function M.decorateDriver(driver, jade)
    if not driver.execute then return driver end

    local original_execute = driver.execute

    driver.execute = function(self_, sql, bindings)
        -- beforeQuery
        M.fire("beforeQuery", { sql = sql, bindings = bindings or {} })

        -- Execute
        local result_ = original_execute(self_, sql, bindings)

        -- afterQuery
        M.fire("afterQuery", { sql = sql, bindings = bindings or {}, rows = result_ })

        return result_
    end

    return driver
end

--- Decorate an entity's create/update/delete with CRUD hooks.
--- Used by plugins that need lifecycle interception without touching Callbacks.
--- @param entity table
--- @return table The decorated entity
function M.decorateEntity(entity)
    -- Store reference for hook scoping
    if not entity._plugin_hooks then
        entity._plugin_hooks = {}
    end

    -- Store extend hooks
    if not entity._plugin_extend_hooks then
        entity._plugin_extend_hooks = {}
    end

    -- We don't override core methods here because the plugin wrapper does it.
    -- This decorator just marks the entity as plugin-aware.
    return entity
end

return M
