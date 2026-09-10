--- Plugin Loader — discovers and loads plugins from configuration.
---
--- Supports three sources:
--- 1. **builtin** — require("jade.plugin.X") via name registry
--- 2. **external** — filesystem path (dofile)
--- 3. **luarocks** — convention jade-plugin-{name}
---
--- Config format (options are top-level OR nested under `options`):
---   plugins = {
---       { name = "cache", ttl = 300, max_size = 2000 },
---       { name = "timestamps" },
---       { name = "my-feature", source = "external", path = "./plugins", foo = 1 },
---   }

local M = {}

M._builtins = {
    ["soft-delete"]     = "jade.plugin.soft_delete",
    ["callbacks"]       = "jade.plugin.callbacks",
    ["optimistic-lock"] = "jade.plugin.optimistic_lock",
    ["audit"]           = "jade.plugin.audit",
    ["encryption"]      = "jade.plugin.encryption",
    ["cache"]           = "jade.plugin.cache",
    ["timestamps"]      = "jade.plugin.timestamps",
    ["tenant"]          = "jade.plugin.tenant",
    ["sql-log"]         = "jade.plugin.sql_log",
}

local RESERVED_KEYS = {
    name = true,
    source = true,
    path = true,
    spec = true,
    options = true,
}

--- Merge plugin config into a plain options table.
--- Accepts either nested `options = { ... }` or top-level keys (except reserved).
--- @param cfg table
--- @return table options
function M.extractOptions(cfg)
    if type(cfg.options) == "table" then
        return cfg.options
    end
    local opts = {}
    for k, v in pairs(cfg) do
        if not RESERVED_KEYS[k] then
            opts[k] = v
        end
    end
    return opts
end

--- Load all plugins from config.
--- @param jade table Jade instance (has .use)
--- @param plugins_config table|nil
--- @return table results Map name -> { ok, error? }
function M.loadAll(jade, plugins_config)
    if not plugins_config or type(plugins_config) ~= "table" then
        return {}
    end

    local results = {}

    for _, cfg in ipairs(plugins_config) do
        local name = cfg.name
        if not name or name == "" then
            results["#" .. tostring(_)] = { ok = false, error = "plugin config missing 'name'" }
        else
            local plugin_module, find_err = M.find(cfg)
            if not plugin_module then
                results[name] = {
                    ok = false,
                    error = find_err or ("plugin '" .. name .. "' could not be found"),
                }
            else
                local opts = M.extractOptions(cfg)
                local ok, err = jade.use(plugin_module, opts)
                results[name] = { ok = ok, error = err }
            end
        end
    end

    return results
end

--- Resolve a plugin module from config entry.
--- @param cfg table
--- @return table|nil module
--- @return string|nil error
function M.find(cfg)
    local name = cfg.name
    local source = cfg.source or "builtin"

    if source == "builtin" or source == "default" then
        local module_path = M._builtins[name]
        if not module_path then
            return nil, "'" .. name .. "' is not registered as a builtin plugin"
        end
        local ok, mod = pcall(require, module_path)
        if not ok then
            return nil, "failed to require builtin plugin '" .. name .. "': " .. tostring(mod)
        end
        return mod
    end

    if source == "external" then
        if not cfg.path then
            return nil, "external plugin '" .. name .. "' requires 'path' config"
        end
        return M._loadExternal(name, cfg.path)
    end

    if source == "luarocks" then
        local spec = cfg.spec or ("luarocks://" .. M._rockspec(name))
        return M._loadLuarocks(spec, cfg)
    end

    return nil, "unknown plugin source: '" .. source .. "'"
end

function M._rockspec(name)
    return "jade-plugin-" .. name
end

--- Load external plugin via dofile (filesystem), not package.path require.
--- @param name string
--- @param load_path string Directory or file path
--- @return table|nil
--- @return string|nil error
function M._loadExternal(name, load_path)
    local candidates = {
        load_path,
        load_path .. "/" .. name .. ".lua",
        load_path .. "/init.lua",
        load_path .. "/" .. name .. "/init.lua",
    }

    local last_err
    for _, path in ipairs(candidates) do
        local chunk, err = loadfile(path)
        if chunk then
            local ok, mod = pcall(chunk)
            if ok and type(mod) == "table" then
                return mod
            end
            if ok then
                last_err = "external plugin '" .. path .. "' did not return a table"
            else
                last_err = tostring(mod)
            end
        else
            last_err = err
        end
    end

    return nil, "external plugin '" .. name .. "' not found at '" .. load_path .. "': " .. tostring(last_err)
end

--- Try require for a luarocks-installed module.
--- @param spec string
--- @param cfg table
--- @return table|nil
--- @return string|nil error
function M._loadLuarocks(spec, cfg)
    local rock_name = spec:gsub("^luarocks://", "")
    local module_path = "jade.plugin." .. rock_name:gsub("^jade%-plugin%-", ""):gsub("%-", "_")

    local ok, mod = pcall(require, module_path)
    if ok and type(mod) == "table" then
        return mod
    end
    return nil, "luarocks plugin '" .. rock_name .. "' not installed (require failed)"
end

return M
