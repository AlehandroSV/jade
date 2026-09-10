--- Jade Plugin: Timestamps
--- Auto-fills created_at / updated_at on create and update.
---
--- Usage:
---   Jade.use(require("jade.plugin.timestamps"), { created_at = "created_at", updated_at = "updated_at" })

local M = {}

M.name        = "timestamps"
M.version     = "1.0.0"
M.description = "Automatic created_at / updated_at on create and update"

local created_col = "created_at"
local updated_col = "updated_at"

local function now()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

M.hooks = {
    beforeCreate = function(ctx)
        local data = ctx.data
        if type(data) ~= "table" then return end
        if data[created_col] == nil then data[created_col] = now() end
        if data[updated_col] == nil then data[updated_col] = now() end
    end,
    beforeUpdate = function(ctx)
        local data = ctx.data
        if type(data) ~= "table" then return end
        data[updated_col] = now()
    end,
}

function M.setup(jade, opts)
    if opts and opts.created_at then created_col = opts.created_at end
    if opts and opts.updated_at then updated_col = opts.updated_at end
    return true
end

function M.teardown(jade)
end

return M
