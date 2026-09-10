local M = {}
local errors = require("jade.errors")

--- Run a single migration within a transaction.
-- Automatically commits on success, rolls back on error.
--
-- Note: MySQL DDL statements (CREATE TABLE, DROP TABLE, ALTER TABLE, etc.)
-- cause implicit commits and cannot be rolled back. Migrations containing
-- DDL on MySQL are not fully atomic. PostgreSQL and SQLite support
-- transactional DDL and are fully atomic.
--
-- @param driver table The database driver
-- @param migration_module table The migration module with up/down functions
-- @param action string The action to perform ("up" or "down")
-- @param opts table|nil Optional `{ after = function(driver) end }` run inside
--   the same transaction after the migration succeeds (e.g. tracker writes)
-- @return boolean true if the migration was committed successfully
function M.run(driver, migration_module, action, opts)
    action = action or "up"

    local fn = migration_module[action]
    if not fn then
        errors.raise(errors.MIGRATION_FILE_INVALID, {
            error = "Migration does not have a '" .. action .. "' function",
        }, 2)
    end

    local after = opts and opts.after
    if after then
        -- Migration DDL + tracker write commit or roll back together
        return driver:transaction(function()
            fn()
            after(driver)
        end)
    end

    -- Execute the migration within a transaction for atomicity
    return driver:transaction(fn)
end

function M.runAll(driver, migrations, action)
    action = action or "up"
    local results = {}

    for _, migration in ipairs(migrations) do
        local ok, err = pcall(function()
            M.run(driver, migration.module, action)
        end)

        results[#results + 1] = {
            name = migration.name,
            success = ok,
            error = err,
        }

        if not ok then
            if type(err) == "table" and err.code then
                error(err, 0)
            end
            errors.raise(errors.MIGRATION_FAILED, {
                name = migration.name,
                error = tostring(err),
            }, 2)
        end
    end

    return results
end

return M
