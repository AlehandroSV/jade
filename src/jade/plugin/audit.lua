--- Jade Plugin: Audit
--- Wraps audit/init.lua as a pluggable module.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.audit"), { ignore = {"password", "ssn"} })
---
--- Creates `jade_audit_logs` table on first write (auto-created).
--- Tracks create/update/delete actions with field-level change snapshots.

local BaseAudit = require("jade.audit")

local M = {}

M.name        = "audit"
M.version     = "1.0.0"
M.description = "Audit trail logging for entity CRUD operations"

-- Hooks: audit works by registering beforeCreate/afterCreate/etc. callbacks.
-- These get installed via extendEntity hook during entity construction.
M.hooks = {
    -- ExtendEntity runs once per entity; audit registers callbacks there
    extendEntity = function(context_)
        BaseAudit.setup(context_.entity, context_.options or {})
    end,
}

--- Install audit globally — it will register callbacks on each entity via hooks.
--- @param jade table The plugin API instance
--- @param options table|nil { ignore? } Fields to exclude from audit logging
--- @return boolean ok
function M.setup(jade, options)
    return true
end

function M.teardown(jade)
    -- No state to clean up.
end

--- Query audit logs (convenience wrapper around BaseAudit.query)
--- @param driver table The database driver
--- @param filters table|nil { table_name?, record_id?, action? }
--- @return table Results
function M.query(driver, filters)
    return BaseAudit.query(driver, filters)
end

return M
