local M = {}

-- Cache stores
local stores = {}

-- Default config
local default_config = {
    driver = "memory",
    ttl = 300,
    max_size = 1000,
}

local config = nil

-- Deep merge tables
local function deepMerge(a, b)
    local result = {}
    for k, v in pairs(a) do result[k] = v end
    for k, v in pairs(b) do result[k] = v end
    return result
end

-- Initialize cache with config
function M.configure(opts)
    config = deepMerge(default_config, opts or {})
end

-- Get config (lazy init)
local function getConfig()
    if not config then
        config = deepMerge(default_config, {})
    end
    return config
end

-- Simple memory cache store
local MemoryStore = {}
MemoryStore.__index = MemoryStore

function MemoryStore.new(opts)
    return setmetatable({
        data = {},
        ttls = {},
        max_size = opts.max_size or 1000,
    }, MemoryStore)
end

function MemoryStore:get(key)
    local entry = self.data[key]
    if entry == nil then return nil end
    if self.ttls[key] and os.time() > self.ttls[key] then
        self.data[key] = nil
        self.ttls[key] = nil
        return nil
    end
    return entry.value
end

function MemoryStore:set(key, value, ttl)
    if not self.data[key] and self:size() >= self.max_size then
        self:evict()
    end
    self.data[key] = { value = value }
    if ttl then
        self.ttls[key] = os.time() + ttl
    end
end

function MemoryStore:delete(key)
    self.data[key] = nil
    self.ttls[key] = nil
end

function MemoryStore:invalidatePattern(pattern)
    local prefix = pattern:gsub("%*.*$", "")
    local keys_to_delete = {}
    for key in pairs(self.data) do
        if key:sub(1, #prefix) == prefix then
            keys_to_delete[#keys_to_delete + 1] = key
        end
    end
    for _, key in ipairs(keys_to_delete) do
        self:delete(key)
    end
    return #keys_to_delete
end

function MemoryStore:size()
    local count = 0
    for _ in pairs(self.data) do count = count + 1 end
    return count
end

function MemoryStore:evict()
    local oldest_key, oldest_time
    for key in pairs(self.data) do
        local ttl = self.ttls[key] or math.huge
        if not oldest_time or ttl < oldest_time then
            oldest_key = key
            oldest_time = ttl
        end
    end
    if oldest_key then
        self:delete(oldest_key)
    end
end

function MemoryStore:clear()
    self.data = {}
    self.ttls = {}
end

-- Store factory
local function getStore()
    local cfg = getConfig()
    local store_key = cfg.driver
    if not stores[store_key] then
        if cfg.driver == "memory" then
            stores[store_key] = MemoryStore.new(cfg)
        else
            error("Cache driver '" .. cfg.driver .. "' not supported. Use 'memory'.")
        end
    end
    return stores[store_key]
end

-- Public API

function M.get(key)
    return getStore():get(key)
end

function M.set(key, value, ttl)
    local cfg = getConfig()
    return getStore():set(key, value, ttl or cfg.ttl)
end

function M.delete(key)
    return getStore():delete(key)
end

function M.invalidatePattern(pattern)
    return getStore():invalidatePattern(pattern)
end

function M.clear()
    return getStore():clear()
end

function M.keygen(prefix, parts)
    local strs = { prefix }
    for _, part in ipairs(parts) do
        strs[#strs + 1] = tostring(part)
    end
    return table.concat(strs, ":")
end

function M._reset()
    stores = {}
    config = nil
end

return M
