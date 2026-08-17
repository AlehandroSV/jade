local M = {}

--- Minimum viable plugin: declares the required fields without any methods.
--- A "bare" table { name = "foo", version = "1.0.0" } satisfies this contract.

M.PLUGIN_INTERFACE = {
    -- Required
    name    = nil,   -- string: unique plugin identifier (e.g. "soft-delete")
    version = nil,   -- string: semver (e.g. "1.0.0")

    -- Optional
    description = "", -- string: short description
    author      = "", -- string: author name
    license     = "", -- string: SPDX license identifier

    -- Lifecycle methods
    setup     = nil,   -- function(jade, options): return ok, error?
    teardown  = nil,   -- function(jade): void
    before_install = nil, -- function(jade, opts): validation before install
    after_install  = nil, -- function(jade): post-install actions

    -- Hooks (populated internally by the hook registry)
    hooks = nil,  -- table of arrays keyed by hook type
}

--- Validate that a plugin table satisfies the minimum interface.
--- @param plugin table|module The plugin to validate
--- @return boolean ok
--- @return string|nil error Message if invalid
function M.validate(plugin)
    if type(plugin) ~= "table" then
        return false, tostring(plugin) .. " is not a table"
    end

    if not plugin.name or type(plugin.name) ~= "string" then
        return false, "plugin missing 'name' (string)"
    end

    if not plugin.version or type(plugin.version) ~= "string" then
        return false, "plugin '" .. plugin.name .. "' missing 'version' (string)"
    end

    if plugin.setup and type(plugin.setup) ~= "function" then
        return false, "plugin '" .. plugin.name .. "' 'setup' must be a function"
    end

    if plugin.teardown and type(plugin.teardown) ~= "function" then
        return false, "plugin '" .. plugin.name .. "' 'teardown' must be a function"
    end

    return true
end

--- Create a new plugin table with defaults.
--- Plugins loaded from luarocks should implement their own name/version,
--- but this helper is useful for tests and inline plugins.
--- @param opts table { name, version, description?, author?, license? }
--- @return table plugin
function M.new(opts)
    if type(opts) ~= "table" or not opts.name then
        error("plugin name is required")
    end
    if not opts.version then
        error("plugin version is required")
    end

    local plugin = {
        name        = opts.name,
        version     = opts.version,
        description = opts.description or ("Plugin: " .. opts.name),
        author      = opts.author or "",
        license     = opts.license or "MIT",
        hooks       = nil,  -- populated by hook registry when registered
    }

    function plugin.setup(jade, options)
        -- Override in actual plugin implementation
        return true
    end

    function plugin.teardown(jade)
        -- Override in actual plugin implementation
    end

    return plugin
end

return M
