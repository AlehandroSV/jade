local M = {}

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
-- @return boolean true if the migration was committed successfully
function M.run(driver, migration_module, action)
    action = action or "up"

    local fn = migration_module[action]
    if not fn then
        error("Migration does not have a '" .. action .. "' function")
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
            error("Migration failed: " .. migration.name .. "\n" .. tostring(err))
        end
    end

    return results
end

return M
