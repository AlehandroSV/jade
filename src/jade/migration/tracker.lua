local M = {}

function M.createTrackerTable(driver)
    local sql = [[
        CREATE TABLE IF NOT EXISTS _jade_migrations (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) UNIQUE NOT NULL,
            jade_version VARCHAR(20),
            applied_at TIMESTAMPTZ DEFAULT NOW()
        )
    ]]
    driver:execute(sql)

    -- Add jade_version column if it doesn't exist (migration for existing tables)
    local check = driver:execute(
        "SELECT column_name FROM information_schema.columns WHERE table_name = '_jade_migrations' AND column_name = 'jade_version'"
    )
    if #check == 0 then
        driver:execute("ALTER TABLE _jade_migrations ADD COLUMN jade_version VARCHAR(20)")
    end
end

function M.getAppliedMigrations(driver)
    local sql = "SELECT name FROM _jade_migrations ORDER BY id"
    local result = driver:execute(sql)
    local applied = {}
    for _, row in ipairs(result) do
        applied[row.name] = true
    end
    return applied
end

function M.recordMigration(driver, name)
    -- Get Jade version without requiring jade (avoids circular dependency)
    local version = "unknown"
    local ok, versionModule = pcall(require, "jade._VERSION")
    if ok and versionModule then
        version = versionModule
    end
    local sql = "INSERT INTO _jade_migrations (name, jade_version) VALUES (?, ?)"
    return driver:execute(sql, { name, version })
end

function M.removeMigration(driver, name)
    local sql = "DELETE FROM _jade_migrations WHERE name = ?"
    return driver:execute(sql, { name })
end

function M.getLastApplied(driver, count)
    count = count or 1
    local sql = "SELECT name FROM _jade_migrations ORDER BY id DESC LIMIT " .. tostring(count)
    local result = driver:execute(sql)
    local names = {}
    for _, row in ipairs(result) do
        names[#names + 1] = row.name
    end
    return names
end

return M
