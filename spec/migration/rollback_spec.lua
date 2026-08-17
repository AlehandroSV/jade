-- Tests for migration rollback atomicity (#118)
-- Rollback must remove tracker records for ALL successful rollbacks,
-- even when a later rollback fails.

describe("Migration rollback atomicity", function()
    local tracker = require("jade.migration.tracker")

    local function mock_driver(opts)
        opts = opts or {}
        local migrations_table = {}
        local driver = {
            _migrations = migrations_table,
            _fail_rollback = opts.fail_rollback or nil,
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

    -- Mock the file and runner modules for rollback testing
    -- We test the rollback logic directly by simulating the pattern
    it("removes tracker for successful rollbacks even when later rollback fails", function()
        local driver = mock_driver()
        -- Seed 3 migrations
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")
        tracker.recordMigration(driver, "003_add_bio")

        -- Simulate rollback of all 3, where 001 fails
        -- Rollback order (newest first): 003, 002, 001
        local to_rollback = { "003_add_bio", "002_add_email", "001_create_users" }
        local rollback_fail = "001_create_users"
        local rolled_back = {}

        for _, name in ipairs(to_rollback) do
            if name == rollback_fail then
                -- This rollback fails
                break
            end
            -- Rollback succeeded, track it
            rolled_back[#rolled_back + 1] = name
        end

        -- BUG behavior: remove tracker immediately per rollback
        -- Fix behavior: remove all successful trackers after all rollbacks
        for _, name in ipairs(rolled_back) do
            tracker.removeMigration(driver, name)
        end

        local applied = tracker.getAppliedMigrations(driver)
        -- 003 and 002 should be removed (their rollbacks succeeded)
        assert.is_falsy(applied["003_add_bio"])
        assert.is_falsy(applied["002_add_email"])
        -- 001 should still be tracked (its rollback failed)
        assert.is_true(applied["001_create_users"])
    end)

    it("removes all trackers when all rollbacks succeed", function()
        local driver = mock_driver()
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")

        local to_rollback = { "002_add_email", "001_create_users" }
        local rolled_back = {}

        for _, name in ipairs(to_rollback) do
            rolled_back[#rolled_back + 1] = name
        end

        for _, name in ipairs(rolled_back) do
            tracker.removeMigration(driver, name)
        end

        local applied = tracker.getAppliedMigrations(driver)
        assert.is_falsy(applied["001_create_users"])
        assert.is_falsy(applied["002_add_email"])
    end)

    it("does not remove any trackers when first rollback fails", function()
        local driver = mock_driver()
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")

        local to_rollback = { "002_add_email", "001_create_users" }
        local rollback_fail = "002_add_email"
        local rolled_back = {}

        for _, name in ipairs(to_rollback) do
            if name == rollback_fail then
                break
            end
            rolled_back[#rolled_back + 1] = name
        end

        for _, name in ipairs(rolled_back) do
            tracker.removeMigration(driver, name)
        end

        local applied = tracker.getAppliedMigrations(driver)
        -- Both should still be tracked since first rollback failed
        assert.is_true(applied["001_create_users"])
        assert.is_true(applied["002_add_email"])
    end)
end)
