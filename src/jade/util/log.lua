local M = {}

local config = {
    enabled = false,
    level = "info",
    format = "text",
    slow_query_threshold = 1000,
    log_bindings = false,
    output = "stdout",
}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

local function should_log(level)
    if not config.enabled then return false end
    return (LEVELS[level] or 0) >= (LEVELS[config.level] or 0)
end

local function format_json(entry)
    local parts = {}
    for k, v in pairs(entry) do
        local val = type(v) == "string" and '"' .. v:gsub('"', '\\"') .. '"' or tostring(v)
        parts[#parts + 1] = '"' .. k .. '":' .. val
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function format_text(entry)
    local ts = os.date("%Y-%m-%d %H:%M:%S")
    local level = (entry.level or "info"):upper()
    local msg = entry.message or entry.sql or ""
    return string.format("[%s] [%s] %s", ts, level, msg)
end

local function emit(entry)
    if type(config.output) == "function" then
        config.output(entry)
    elseif config.output == "file" and config._file then
        local line = config.format == "json" and format_json(entry) or format_text(entry)
        config._file:write(line .. "\n")
        config._file:flush()
    else
        local line = config.format == "json" and format_json(entry) or format_text(entry)
        if entry.level == "error" then
            io.stderr:write(line .. "\n")
        else
            print(line)
        end
    end
end

function M.configure(opts)
    if not opts then return end
    config.enabled = opts.enabled or config.enabled
    config.level = opts.level or config.level
    config.format = opts.format or config.format
    config.slow_query_threshold = opts.slow_query_threshold or config.slow_query_threshold
    config.log_bindings = opts.log_bindings or config.log_bindings
    config.output = opts.output or config.output

    if config.output == "file" and opts.log_file then
        config._file = io.open(opts.log_file, "a")
    end
end

function M.setDebug(enabled)
    config.enabled = enabled
    if enabled then config.level = "debug" end
end

function M.query(sql, bindings, duration_ms)
    if not should_log("info") then return end

    local entry = {
        type = "query",
        sql = sql,
        duration_ms = duration_ms,
    }

    if config.log_bindings and bindings and #bindings > 0 then
        local parts = {}
        for _, v in ipairs(bindings) do parts[#parts + 1] = tostring(v) end
        entry.bindings = table.concat(parts, ",")
    end

    emit(entry)

    if duration_ms and duration_ms >= config.slow_query_threshold then
        entry.type = "slow_query"
        entry.threshold = config.slow_query_threshold
        entry.level = "warn"
        emit(entry)
    end
end

function M.sql(sql, bindings)
    if not should_log("debug") then return end
    local entry = { type = "query", sql = sql, level = "debug" }
    if config.log_bindings and bindings and #bindings > 0 then
        local parts = {}
        for _, v in ipairs(bindings) do parts[#parts + 1] = tostring(v) end
        entry.bindings = table.concat(parts, ",")
    end
    emit(entry)
end

function M.info(msg)
    if not should_log("info") then return end
    emit({ level = "info", message = msg })
end

function M.warn(msg)
    if not should_log("warn") then return end
    emit({ level = "warn", message = msg })
end

function M.error(msg)
    if not should_log("error") then return end
    emit({ level = "error", message = msg })
end

function M.pool_acquire(pool_size, available)
    if not should_log("debug") then return end
    emit({ type = "pool.acquire", pool_size = pool_size, available = available, level = "debug" })
end

function M.pool_release(pool_size, available)
    if not should_log("debug") then return end
    emit({ type = "pool.release", pool_size = pool_size, available = available, level = "debug" })
end

function M.cache_hit(key)
    if not should_log("debug") then return end
    emit({ type = "cache.hit", key = key, level = "debug" })
end

function M.cache_miss(key)
    if not should_log("debug") then return end
    emit({ type = "cache.miss", key = key, level = "debug" })
end

function M.migration_run(name, duration_ms)
    if not should_log("info") then return end
    emit({ type = "migration.run", name = name, duration_ms = duration_ms, level = "info" })
end

return M
