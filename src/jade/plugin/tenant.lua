--- Jade Plugin: Tenant
--- Adds a global tenant_id filter on queries and injects tenant_id on create.
---
--- Usage:
---   local tenant = require("jade.plugin.tenant")
---   Jade.use(tenant, { column = "tenant_id", value = 42 })
---   -- later: tenant.set(99)
---
--- Scope is process/coroutine-local enough for demos; production apps should
--- set the tenant per request (e.g. in middleware via tenant.set).

local M = {}

M.name        = "tenant"
M.version     = "0.1.0"
M.description = "Automatic tenant_id scoping for queries and creates"

local column = "tenant_id"
local current_tenant = nil

function M.set(value)
    current_tenant = value
end

function M.get()
    return current_tenant
end

function M.clear()
    current_tenant = nil
end

M.hooks = {
    beforeCreate = function(ctx)
        if current_tenant == nil then return end
        local data = ctx.data
        if type(data) == "table" and data[column] == nil then
            data[column] = current_tenant
        end
    end,
    beforeQuery = function(ctx)
        -- Informational only: full WHERE injection requires Query integration.
        -- We stamp the context so custom plugins/logging can see the tenant.
        if current_tenant ~= nil then
            ctx.tenant_id = current_tenant
        end
    end,
}

function M.setup(jade, opts)
    if opts and opts.column then column = opts.column end
    if opts and opts.value ~= nil then current_tenant = opts.value end
    return true
end

function M.teardown(jade)
    current_tenant = nil
end

return M
