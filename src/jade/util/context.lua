-- Coroutine-safe context storage for Jade
-- Uses ngx.ctx when running inside OpenResty, falls back to coroutine-local state

local M = {}

-- Check if ngx is available
local ok_ngx, ngx = pcall(require, "ngx")
if not ok_ngx then
    ngx = nil
end

-- Coroutine-local storage for non-OpenResty environments
-- Uses coroutine as key to ensure isolation between coroutines
local _coroutine_ctx = {}

local function get_coroutine_key()
    local co = coroutine.running()
    if co then
        return co
    end
    -- Main thread doesn't have a coroutine, use a special key
    return "__main__"
end

local function is_openresty()
    return ngx and ngx.ctx
end

function M.get(key)
    if is_openresty() then
        return ngx.ctx["jade_" .. key]
    end
    local co_key = get_coroutine_key()
    local ctx = _coroutine_ctx[co_key]
    if ctx then
        return ctx[key]
    end
    return nil
end

function M.set(key, value)
    if is_openresty() then
        ngx.ctx["jade_" .. key] = value
    else
        local co_key = get_coroutine_key()
        if not _coroutine_ctx[co_key] then
            _coroutine_ctx[co_key] = {}
        end
        _coroutine_ctx[co_key][key] = value
    end
end

function M.clear()
    if is_openresty() then
        ngx.ctx["jade_driver"] = nil
        ngx.ctx["jade_config"] = nil
    else
        local co_key = get_coroutine_key()
        _coroutine_ctx[co_key] = nil
    end
end

return M
