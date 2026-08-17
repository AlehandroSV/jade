-- Coroutine-safe context storage for Jade
-- Uses ngx.ctx when running inside OpenResty, falls back to module-level state

local M = {}

local _fallback_ctx = {}

local function is_openresty()
    return pcall(require, "ngx") and ngx and ngx.ctx
end

function M.get(key)
    if is_openresty() then
        return ngx.ctx["jade_" .. key]
    end
    return _fallback_ctx[key]
end

function M.set(key, value)
    if is_openresty() then
        ngx.ctx["jade_" .. key] = value
    else
        _fallback_ctx[key] = value
    end
end

function M.clear()
    if is_openresty() then
        ngx.ctx["jade_driver"] = nil
        ngx.ctx["jade_config"] = nil
    else
        _fallback_ctx = {}
    end
end

return M
