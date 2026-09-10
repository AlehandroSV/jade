--- Jade Plugin: SQL Log
--- Logs every SQL statement via jade.log (structured, English).
---
--- Usage:
---   Jade.use(require("jade.plugin.sql_log"), { level = "info" })

local M = {}

M.name        = "sql-log"
M.version     = "1.0.0"
M.description = "Log SQL queries through jade.log"

local level = "info"

M.hooks = {
    beforeQuery = function(ctx)
        local log = require("jade.util.log")
        log.sql(ctx.sql, ctx.bindings)
    end,
}

function M.setup(jade, opts)
    if opts and opts.level then level = opts.level end
    return true
end

function M.teardown(jade)
end

return M
