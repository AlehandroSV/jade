local tracker = require("jade.migration.tracker")
local runner = require("jade.migration.runner")
local file = require("jade.migration.file")
local diff = require("jade.migration.diff")
local generator = require("jade.migration.generator")

local M = {
    tracker = tracker,
    runner = runner,
    file = file,
    diff = diff,
    generator = generator,
}

function M.init(driver)
    tracker.createTrackerTable(driver)
end

function M.migrate(driver)
    -- Ensure tracker table exists
    tracker.createTrackerTable(driver)

    -- Get applied migrations
    local applied = tracker.getAppliedMigrations(driver)

    -- Get all migration files
    local files = file.listFiles()

    -- Filter to pending migrations
    local pending = {}
    for _, f in ipairs(files) do
        if not applied[f.name] then
            pending[#pending + 1] = f
        end
    end

    if #pending == 0 then
        print("No pending migrations")
        return {}
    end

    -- Run pending migrations
    local results = {}
    for _, f in ipairs(pending) do
        print("Applying: " .. f.name)
        local migration = file.load(f.path)
        local ok, err = pcall(function()
            runner.run(driver, migration, "up")
        end)

        if ok then
            tracker.recordMigration(driver, f.name)
            results[#results + 1] = { name = f.name, success = true }
            print("  Applied: " .. f.name)
        else
            results[#results + 1] = { name = f.name, success = false, error = err }
            print("  Failed: " .. f.name .. "\n  Error: " .. tostring(err))
            error("Migration failed: " .. f.name)
        end
    end

    return results
end

function M.rollback(driver, steps)
    steps = steps or 1

    -- Get last N applied migrations
    local last_applied = tracker.getLastApplied(driver, steps)

    if #last_applied == 0 then
        print("No migrations to rollback")
        return {}
    end

    local results = {}
    for _, name in ipairs(last_applied) do
        print("Rolling back: " .. name)
        local path = "migrations/" .. name
        local ok, err = pcall(function()
            local migration = file.load(path)
            runner.run(driver, migration, "down")
        end)

        if ok then
            tracker.removeMigration(driver, name)
            results[#results + 1] = { name = name, success = true }
            print("  Rolled back: " .. name)
        else
            results[#results + 1] = { name = name, success = false, error = err }
            print("  Failed: " .. name .. "\n  Error: " .. tostring(err))
            error("Rollback failed: " .. name)
        end
    end

    return results
end

function M.preview(driver)
    -- Get applied migrations
    local applied = tracker.getAppliedMigrations(driver)

    -- Get all migration files
    local files = file.listFiles()

    -- Filter to pending migrations
    local pending = {}
    for _, f in ipairs(files) do
        if not applied[f.name] then
            pending[#pending + 1] = f
        end
    end

    if #pending == 0 then
        print("No pending migrations")
        return
    end

    print("Pending migrations:")
    for _, f in ipairs(pending) do
        print("  - " .. f.name)
    end
end

function M.status(driver)
    tracker.createTrackerTable(driver)
    local applied = tracker.getAppliedMigrations(driver)
    local files = file.listFiles()

    local pending = {}
    for _, f in ipairs(files) do
        if not applied[f.name] then
            pending[#pending + 1] = f
        end
    end

    local applied_count = 0
    for _ in pairs(applied) do applied_count = applied_count + 1 end
    print("Applied: " .. tostring(applied_count))
    print("Pending: " .. tostring(#pending))

    if #pending > 0 then
        print("\nPending migrations:")
        for _, f in ipairs(pending) do
            print("  - " .. f.name)
        end
    end
end

return M
