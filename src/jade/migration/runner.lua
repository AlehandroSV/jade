local M = {}

function M.run(_driver, migration_module, action)
    action = action or "up"

    local fn = migration_module[action]
    if not fn then
        error("Migration does not have a '" .. action .. "' function")
    end

    -- Execute the migration function
    -- The function should call Jade API methods like createTable, etc.
    fn()

    return true
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
