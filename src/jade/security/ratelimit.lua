--- Rate Limiting Module for Jade ORM
--- Provides optional query rate limiting to prevent DoS attacks
--- @module jade.security.ratelimit

local M = {}

-- Default configuration
local config = {
    enabled = false,
    max_queries_per_second = 100,
    max_queries_per_minute = 1000,
    burst_size = 50,
}

-- Token bucket state per connection/user
local buckets = {}
local cleanup_interval = 60 -- seconds
local last_cleanup = os.time()

-- Initialize rate limiter with custom configuration
--- @param opts table Configuration options
--- @return boolean Success
function M.init(opts)
    opts = opts or {}
    config.enabled = opts.enabled or false
    config.max_queries_per_second = opts.max_queries_per_second or 100
    config.max_queries_per_minute = opts.max_queries_per_minute or 1000
    config.burst_size = opts.burst_size or 50
    return true
end

-- Get or create a token bucket for a key (connection/user identifier)
local function getBucket(key)
    local now = os.time()
    
    -- Cleanup old buckets periodically
    if now - last_cleanup > cleanup_interval then
        for k, bucket in pairs(buckets) do
            if now - bucket.last_access > cleanup_interval * 2 then
                buckets[k] = nil
            end
        end
        last_cleanup = now
    end
    
    if not buckets[key] then
        buckets[key] = {
            tokens = config.burst_size,
            last_update = now,
            queries_this_second = 0,
            queries_this_minute = 0,
            current_second = now,
            current_minute = now,
            last_access = now,
        }
    end
    
    return buckets[key]
end

-- Refill tokens based on elapsed time (token bucket algorithm)
local function refillTokens(bucket, now)
    local elapsed = now - bucket.last_update
    
    -- Add tokens based on time elapsed (max_queries_per_second tokens per second)
    local tokens_to_add = elapsed * config.max_queries_per_second
    bucket.tokens = math.min(config.burst_size, bucket.tokens + tokens_to_add)
    bucket.last_update = now
    
    -- Reset per-second counter
    if now - bucket.current_second >= 1 then
        bucket.queries_this_second = 0
        bucket.current_second = now
    end
    
    -- Reset per-minute counter
    if now - bucket.current_minute >= 60 then
        bucket.queries_this_minute = 0
        bucket.current_minute = now
    end
end

-- Check if a query is allowed for the given key
--- @param key string Identifier (e.g., connection ID, user ID, IP)
--- @return boolean allowed Whether the query is allowed
--- @return number? retry_after Seconds until retry is allowed (if blocked)
function M.allow(key)
    if not config.enabled then
        return true, nil
    end
    
    local now = os.time()
    local bucket = getBucket(key)
    refillTokens(bucket, now)
    bucket.last_access = now
    
    -- Check per-second limit
    if bucket.queries_this_second >= config.max_queries_per_second then
        return false, 1
    end
    
    -- Check per-minute limit
    if bucket.queries_this_minute >= config.max_queries_per_minute then
        return false, 60
    end
    
    -- Check token bucket (burst protection)
    if bucket.tokens < 1 then
        local tokens_needed = 1 - bucket.tokens
        local wait_time = tokens_needed / config.max_queries_per_second
        return false, math.ceil(wait_time)
    end
    
    -- Consume token and increment counters
    bucket.tokens = bucket.tokens - 1
    bucket.queries_this_second = bucket.queries_this_second + 1
    bucket.queries_this_minute = bucket.queries_this_minute + 1
    
    return true, nil
end

-- Check rate limit and throw error if exceeded
--- @param key string Identifier
--- @raise Error if rate limit exceeded
function M.check(key)
    local allowed, retry_after = M.allow(key)
    if not allowed then
        error(string.format(
            "Rate limit exceeded. Retry after %d seconds",
            retry_after or 1
        ))
    end
end

-- Get current rate limit status for a key
--- @param key string Identifier
--- @return table Status information
function M.getStatus(key)
    if not config.enabled then
        return { enabled = false }
    end
    
    local bucket = getBucket(key)
    local now = os.time()
    refillTokens(bucket, now)
    
    return {
        enabled = true,
        tokens_available = math.floor(bucket.tokens),
        queries_this_second = bucket.queries_this_second,
        queries_this_minute = bucket.queries_this_minute,
        max_per_second = config.max_queries_per_second,
        max_per_minute = config.max_queries_per_minute,
        burst_size = config.burst_size,
    }
end

-- Reset rate limit for a specific key
--- @param key string Identifier
function M.reset(key)
    buckets[key] = nil
end

-- Clear all rate limit data (useful for testing)
function M.clear()
    buckets = {}
    last_cleanup = os.time()
end

-- Enable rate limiting
function M.enable()
    config.enabled = true
end

-- Disable rate limiting
function M.disable()
    config.enabled = false
end

-- Check if rate limiting is enabled
--- @return boolean
function M.isEnabled()
    return config.enabled
end

return M
