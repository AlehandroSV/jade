-- Tests for migration rollback atomicity (#118)
-- Rollback must remove tracker records for ALL successful rollbacks,
-- even when a later rollback fails.

describe("Migration rollback atomicity", function()
    local tracker = require("jade.migration.tracker")
    local M = require("jade.migration")

    local function mock_driver()
        local migrations_table = {}
        local driver = {
            _migrations = migrations_table,
        }

        function driver:execute(sql, bindings)
            if sql:match("CREATE TABLE") then
                return {}
            elseif sql:match("INSERT INTO _jade_migrations") then
                migrations_table[#migrations_table + 1] = { name = bindings[1] }
                return {}
            elseif sql:match("DELETE FROM _jade_migrations") then
                for i, row in ipairs(migrations_table) do
                    if row.name == bindings[1] then
                        table.remove(migrations_table, i)
                        break
                    end
                end
                return {}
            elseif sql:match("SELECT name FROM _jade_migrations ORDER BY id DESC") then
                local limit = tonumber(sql:match("LIMIT (%d+)")) or #migrations_table
                local result = {}
                local count = 0
                for i = #migrations_table, 1, -1 do
                    count = count + 1
                    if count > limit then break end
                    result[#result + 1] = { name = migrations_table[i].name }
                end
                return result
            elseif sql:match("SELECT name FROM _jade_migrations") then
                local result = {}
                for _, row in ipairs(migrations_table) do
                    result[#result + 1] = { name = row.name }
                end
                return result
            end
            return {}
        end

        return driver
    end

    -- Save original modules for restoration
    local original_file = M.file
    local original_runner = M.runner

    local function setup_mocks(opts)
        opts = opts or {}
        local fail_migration = opts.fail_migration

        -- Mock file module
        M.file = {
            listFiles = function()
                return {
                    { name = "001_create_users", path = "migrations/001_create_users" },
                    { name = "002_add_email", path = "migrations/002_add_email" },
                    { name = "003_add_bio", path = "migrations/003_add_bio" },
                }
            end,
            load = function(path)
                return { name = path:match("([^/]+)$") }
            end,
        }

        -- Mock runner module
        M.runner = {
            run = function(driver, migration, direction)
                if fail_migration and migration.name == fail_migration then
                    error("Migration failed: " .. migration.name)
                end
                return true
            end,
        }
    end

    after_each(function()
        M.file = original_file
        M.runner = original_runner
    end)

    it("removes tracker for successful rollbacks even when later rollback fails", function()
        local driver = mock_driver()
        setup_mocks({ fail_migration = "001_create_users" })

        -- Seed 3 migrations
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")
        tracker.recordMigration(driver, "003_add_bio")

        -- Rollback all 3 - 001 will fail
        local ok, err = pcall(function()
            M.rollback(driver, 3)
        end)

        -- Should have thrown an error for the failed migration
        assert.is_falsy(ok)
        assert.is_truthy(err:find("Rollback failed: 001_create_users"))

        local applied = tracker.getAppliedMigrations(driver)
        -- 003 and 002 should be removed (their rollbacks succeeded)
        assert.is_falsy(applied["003_add_bio"])
        assert.is_falsy(applied["002_add_email"])
        -- 001 should still be tracked (its rollback failed)
        assert.is_true(applied["001_create_users"])
    end)

    it("removes all trackers when all rollbacks succeed", function()
        local driver = mock_driver()
        setup_mocks()

        -- Seed 2 migrations
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")

        -- Rollback both - should succeed
        M.rollback(driver, 2)

        local applied = tracker.getAppliedMigrations(driver)
        assert.is_falsy(applied["001_create_users"])
        assert.is_falsy(applied["002_add_email"])
    end)

    it("does not remove any trackers when first rollback fails", function()
        local driver = mock_driver()
        setup_mocks({ fail_migration = "003_add_bio" })

        -- Seed 3 migrations
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")
        tracker.recordMigration(driver, "003_add_bio")

        -- Rollback 2 - 003 (newest) will fail first
        local ok, err = pcall(function()
            M.rollback(driver, 2)
        end)

        assert.is_falsy(ok)
        assert.is_truthy(err:find("Rollback failed: 003_add_bio"))

        local applied = tracker.getAppliedMigrations(driver)
        -- All should still be tracked since first rollback failed
        assert.is_true(applied["001_create_users"])
        assert.is_true(applied["002_add_email"])
        assert.is_true(applied["003_add_bio"])
    end)
end)
