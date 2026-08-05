local log = require("jade.util.log")

local M = {}

-- Default retry configuration
local defaults = {
    max_attempts = 1,        -- No retry by default
    delay = 1000,            -- 1 second initial delay
    backoff = "exponential", -- "exponential" or "linear"
    max_delay = 30000,       -- 30 seconds max delay
}

-- Calculate delay for next attempt
function M.calculateDelay(attempt, config)
    local delay = config.delay or defaults.delay
    local backoff = config.backoff or defaults.backoff
    local max_delay = config.max_delay or defaults.max_delay

    if backoff == "exponential" then
        -- Exponential: delay * 2^(attempt-1)
        delay = delay * math.pow(2, attempt - 1)
    else
        -- Linear: delay * attempt
        delay = delay * attempt
    end

    return math.min(delay, max_delay)
end

-- Sleep for specified milliseconds
-- Uses luasocket if available, otherwise busy wait
function M.sleep(ms)
    local ok, socket = pcall(require, "socket")
    if ok and socket then
        socket.sleep(ms / 1000)
    else
        -- Busy wait fallback (not ideal but works without dependencies)
        local start = os.clock()
        local seconds = ms / 1000
        while os.clock() - start < seconds do
            -- busy wait
        end
    end
end

-- Execute a function with retry logic
-- fn: function to execute
-- config: retry configuration table
-- context: string for logging (e.g., "PostgreSQL connection")
function M.execute(fn, config, context)
    config = config or {}
    local max_attempts = config.max_attempts or defaults.max_attempts

    local last_err
    for attempt = 1, max_attempts do
        local ok, result = pcall(fn)

        if ok then
            return result
        end

        last_err = result

        if attempt < max_attempts then
            local delay = M.calculateDelay(attempt, config)
            log.warn("[%s] Attempt %d/%d failed: %s. Retrying in %dms...",
                context or "Retry", attempt, max_attempts, tostring(result), delay)
            M.sleep(delay)
        end
    end

    error(string.format("[%s] Failed after %d attempts: %s",
        context or "Retry", max_attempts, tostring(last_err)))
end

-- Merge retry config from driver config
function M.getConfig(driver_config)
    if driver_config and driver_config.retry then
        return {
            max_attempts = driver_config.retry.max_attempts or defaults.max_attempts,
            delay = driver_config.retry.delay or defaults.delay,
            backoff = driver_config.retry.backoff or defaults.backoff,
            max_delay = driver_config.retry.max_delay or defaults.max_delay,
        }
    end
    return { max_attempts = defaults.max_attempts }
end

return M
