--- Jade Plugin: Cache
--- Wraps cache/init.lua as a pluggable module.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.cache"), { ttl = 600, max_size = 2000 })
---
--- Currently supports in-memory driver only. Future: Redis, Memcached adapters.

local M = {}

M.name        = "cache"
M.version     = "1.0.0"
M.description = "In-memory query result cache with TTL and LRU eviction"

-- The cache module is global — it doesn't need extendEntity hooks.
-- Just needs configure() called once at setup time.
M.hooks = {}

--- Install cache configuration.
--- @param jade table The plugin API instance
--- @param opts table|nil { driver?, ttl?, max_size? }
--- @return boolean ok
function M.setup(jade, opts)
    local Cache = require("jade.cache")

    if not opts then return true end

    -- Validate options
    if opts.driver and opts.driver ~= "memory" then
        return false, "cache driver '" .. tostring(opts.driver) .. "' not yet implemented (only 'memory' available)"
    end

    if opts.ttl and type(opts.ttl) ~= "number" then
        return false, "cache ttl must be a number (seconds)"
    end

    if opts.max_size and type(opts.max_size) ~= "number" then
        return false, "cache max_size must be a number"
    end

    -- Configure underlying cache
    Cache.configure({
        driver  = opts.driver or "memory",
        ttl     = opts.ttl or 300,
        max_size = opts.max_size or 1000,
    })

    return true
end

function M.teardown(jade)
    -- Clear cache on teardown
    local Cache = require("jade.cache")
    pcall(Cache.clear)
end

--- Get cached value by key (convenience).
--- @param key string
--- @return any value|nil
function M.get(key)
    local Cache = require("jade.cache")
    return Cache.get(key)
end

--- Set cached value (convenience).
--- @param key string
--- @param value any
--- @param ttl number|nil Override for this entry
function M.set(key, value, ttl)
    local Cache = require("jade.cache")
    Cache.set(key, value, ttl)
end

--- Delete cached value (convenience).
--- @param key string
function M.delete(key)
    local Cache = require("jade.cache")
    Cache.delete(key)
end

return M
