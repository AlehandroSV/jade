--- Jade Plugin System — Main Entry Point
---
--- Public API:
---   jade.use(plugin, options)      — Install a plugin
---   jade.unloadPlugin(name)        — Uninstall a plugin by name
---   jade.getPlugin(name)           — Get an installed plugin table
---   jade.listPlugins()             — List all installed plugins {name = version}
---   jade.hasPlugin(name)           — Check if a plugin is installed
---
--- Usage:
---   local Jade = require("jade")
---
---   -- From a module path
---   Jade.use(require("jade.plugin.soft_delete"))
---
---   -- With options
---   Jade.use(require("jade.plugin.cache"), { ttl = 600 })
---
---   -- Inline plugin (for testing or quick setup)
---   local Base = require("jade.plugin.base")
---   local my_plugin = Base.new({ name = "my-feature", version = "0.1.0" })
---   function my_plugin.setup(jade, opts)
---       -- feature logic here
---       return true
---   end
---   Jade.use(my_plugin, opts)
---
---   -- Via config file (automatic discovery):
---   --- @field JADE_ENV = "development" | "test" | "production"
---
---     jade.config.{JADE_ENV}.lua:
---     return {
---         database = { ... },
---         plugins = {                          -- optional
---             { name = "soft-delete" },          -- no extra options
---             { name = "cache",    ttl = 300 }, -- custom options
---             { name = "audit",    ignore = {"password"} },
---             { name = "encryption", key = "${ENCRYPTION_KEY}" },
---             -- Plugins auto-discovered from luarocks will be loaded here too
---         }
---     }

local HookRegistry = require("jade.plugin.hooks")
local Base = require("jade.plugin.base")

local M = {}
M._VERSION = "1.0.0"

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- Map of installed plugins: name -> { plugin, options, installed_at }
local installed = {}

---------------------------------------------------------------------------
-- Core API
---------------------------------------------------------------------------

--- Install a plugin into Jade.
--- Validates the plugin interface, registers its hooks, calls setup().
--- @param plugin module|table The plugin module/table (must have name, version, setup?)
--- @param options table|nil Options passed to plugin.setup()
--- @return boolean ok Success status
--- @return string|nil error Error message on failure
function M.use(plugin, options)
    -- Validate
    local ok, err = Base.validate(plugin)
    if not ok then
        return false, err
    end

    local name = plugin.name

    -- Already installed?
    if installed[name] then
        return false, "plugin '" .. name .. "' is already installed"
    end

    -- Register hooks first so setup() can fire them during execution
    if plugin.hooks then
        HookRegistry.registerPlugin(name, plugin.hooks)
    end

    -- Call setup if provided
    if plugin.setup then
        local setup_ok, setup_err = pcall(function()
            return plugin.setup(M, options or {})
        end)
        if not setup_ok then
            HookRegistry.unregister(name)
            return false, "setup error for '" .. name .. "': " .. tostring(setup_err)
        end
        if type(setup_err) == "string" then
            HookRegistry.unregister(name)
            return false, "setup returned error: " .. setup_err
        end
    end

    -- Store installed plugin
    installed[name] = {
        plugin     = plugin,
        options    = options or {},
        installed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }

    return true
end

--- Uninstall a plugin by name. Calls teardown() if available, clears hooks.
--- @param name string
--- @return boolean ok
--- @return string|nil error
function M.unloadPlugin(name)
    local entry = installed[name]
    if not entry then
        return false, "plugin '" .. name .. "' is not installed"
    end

    -- Teardown
    if entry.plugin.teardown then
        pcall(entry.plugin.teardown, M)
    end

    -- Clear hooks
    HookRegistry.unregister(name)

    installed[name] = nil
    return true
end

--- Get an installed plugin's metadata.
--- @param name string
--- @return table|nil entry { plugin, options, installed_at } or nil
function M.getPlugin(name)
    return installed[name]
end

--- List all installed plugins as { [name] = version }.
--- @return table<string, string>
function M.listPlugins()
    local result = {}
    for name_, entry_ in pairs(installed) do
        result[name_] = entry_.plugin.version
    end
    return result
end

--- Check if a plugin is installed.
--- @param name string
--- @return boolean
function M.hasPlugin(name)
    return installed[name] ~= nil
end

--- Get the hook registry for direct access (advanced use).
--- @return table
function M.hooks()
    return HookRegistry
end

--- Apply extension hooks to a driver instance (called after driver creation).
--- @param driver table
--- @return table Decorated driver
function M.applyDriverExtensions(driver)
    return HookRegistry.decorateDriver(driver)
end

--- Apply extension hooks to an entity instance (called after entity construction).
--- @param entity table
--- @return table Decorated entity
function M.applyEntityExtensions(entity)
    return HookRegistry.decorateEntity(entity)
end

return M
