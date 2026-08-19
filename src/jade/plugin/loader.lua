--- Plugin Loader — discovers and loads plugins from configuration.
---
--- This module bridges `jade.config.lua` with the plugin system.
--- It supports three loading strategies:
---
--- 1. **Builtin** (pre-registered in M._builtins): loaded via require("jade.plugin.X")
--- 2. **Luarocks** (from PATH): loaded by resolving luarocks package names like "luarocks://jade-plugin-soft-delete"
--- 3. **External** (filesystem): loaded from a user-specified directory via require(load_path, relative)
---
--- Config format:
---   plugins = {
---       -- Simple: just name (uses builtin registration)
---       { name = "soft-delete" },
---       { name = "cache",     ttl = 300 },
---       { name = "audit",     ignore = {"password"} },
---       -- With explicit source
---       { name = "my-feature", source = "external", path = "./plugins" },
---       -- With luarocks
---       { name = "community-stats", source = "luarocks", spec = "luarocks://jade-plugin-community-stats" },
---   }

local M = {}

-- Builtin plugin registry: maps short names to their module paths
M._builtins = {
    ["soft-delete"]    = "jade.plugin.soft_delete",
    ["callbacks"]      = "jade.plugin.callbacks",
    ["optimistic-lock"]= "jade.plugin.optimistic_lock",
    ["audit"]          = "jade.plugin.audit",
    ["encryption"]     = "jade.plugin.encryption",
    ["cache"]          = "jade.plugin.cache",
}

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

--- Load all plugins configured in a Jade config table.
--- @param jade table The Jade instance (has .use())
--- @param plugins_config table Array of plugin config entries
--- @return table results Map of { [name] = { ok = bool, error? } }
function M.loadAll(jade, plugins_config)
    if not plugins_config or type(plugins_config) ~= "table" then
        return {}
    end

    local results = {}

    for idx_, cfg_ in ipairs(plugins_config) do
        local name_ = cfg_.name
        
        -- Helper lambda-style processing
        local function skip_if_missing()
            if name_ == nil or name_ == "" then
                results[idx_] = { ok = false, error = "plugin config missing 'name'" }
                return true
            end
            
            local plugin_module = M.find(cfg_)
            if not plugin_module then
                results[name_] = { ok = false, error = "plugin '" .. name_ .. "' could not be found" }
                return true
            end
            
            local ok, err = jade.use(plugin_module, cfg_.options or {})
            results[name_] = { ok = ok, error = err }
            return false
        end
        
        skip_if_missing()
    end

    return results
end

--- Find and resolve a plugin module from its config entry.
--- @param cfg table { name, source?, path?, spec? }
--- @return module|nil
--- @return string|nil error
function M.find(cfg)
    local name = cfg.name
    local source = cfg.source or "builtin"

    if source == "builtin" or source == "default" then
        local module_path = M._builtins[name]
        if not module_path then
            return nil, "'" .. name .. "' is not registered as a builtin plugin"
        end
        return require(module_path)
    end

    if source == "external" then
        local load_path = cfg.path
        if not load_path then
            return nil, "external plugin '" .. name .. "' requires 'path' config"
        end
        return M._loadExternal(name, load_path)
    end

    if source == "luarocks" then
        local spec = cfg.spec or ("luarocks://" .. M._rockspec(name))
        return M._loadLuarocks(spec, cfg)
    end

    return nil, "unknown plugin source: '" .. source .. "'"
end

--- Resolve a plugin name to a luarocks rockspec.
--- Convention: jade-plugin-{name} → jade-plugin-name-X.Y.Z-1.rockspec
--- @param name string
--- @return string rockspec
function M._rockspec(name)
    return "jade-plugin-" .. name
end

--- Load an external plugin from filesystem.
--- Tries multiple file patterns for robustness.
--- @param name string
--- @param load_path string
--- @return module|nil
function M._loadExternal(name, load_path)
    local candidates = {
        load_path .. "/" .. name .. ".lua",
        load_path .. "/init.lua",
        load_path .. "/" .. name .. "/init.lua",
    }

    for _, path in ipairs(candidates) do
        local loaded, err = pcall(require, path)
        if loaded then return loaded end
        -- Clear lua's module cache since we don't want it cached
        package.loaded[path] = nil
    end

    return nil
end

--- Attempt to load a plugin from a luarock.
--- In the future this could auto-install the rock; for now it tries require().
--- @param spec string The luarock spec (e.g. "luarocks://jade-plugin-cache")
--- @param cfg table
--- @return module|nil
function M._loadLuarocks(spec, cfg)
    -- Strip "luarocks://" prefix and try to require
    local rock_name = spec:gsub("^luarocks://", "")
    local module_path = "jade.plugin." .. rock_name:gsub("^jade%-plugin%-", "")

    local loaded, err = pcall(require, module_path)
    if loaded then return loaded end

    return nil
end

return M
