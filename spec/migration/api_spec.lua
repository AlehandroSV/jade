-- Tests for migration programmatic API (#91)
-- rollback() and status() should be accessible via Lua API

describe("Migration API", function()
    local migration = require("jade.migration")
    local tracker = require("jade.migration.tracker")

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

    describe("rollback API", function()
        it("rollback is callable", function()
            assert.is_function(migration.rollback)
        end)

        it("rollback accepts steps as number (backward compat)", function()
            local driver = mock_driver()
            tracker.recordMigration(driver, "001_create_users")
            tracker.recordMigration(driver, "002_add_email")

            -- Rollback should work with number argument
            local result = migration.rollback(driver, 1)
            assert.is_truthy(result)
            assert.is_truthy(type(result) == "table")
        end)

        it("rollback accepts options table with steps", function()
            local driver = mock_driver()
            tracker.recordMigration(driver, "001_create_users")
            tracker.recordMigration(driver, "002_add_email")

            -- Rollback should work with options table
            local result = migration.rollback(driver, { steps = 1 })
            assert.is_truthy(result)
            assert.is_truthy(type(result) == "table")
        end)

        it("rollback returns results table", function()
            local driver = mock_driver()
            -- No migrations to rollback
            local results = migration.rollback(driver)
            assert.is_truthy(type(results) == "table")
        end)
    end)

    describe("status API", function()
        it("status is callable", function()
            assert.is_function(migration.status)
        end)

        it("status returns structured data", function()
            local driver = mock_driver()
            tracker.recordMigration(driver, "001_create_users")

            local result = migration.status(driver)
            assert.is_truthy(result)
            assert.is_truthy(result.executed)
            assert.is_truthy(result.pending)
            assert.is_truthy(type(result.executed) == "table")
            assert.is_truthy(type(result.pending) == "table")
        end)

        it("status lists executed migrations", function()
            local driver = mock_driver()
            tracker.recordMigration(driver, "001_create_users")
            tracker.recordMigration(driver, "002_add_email")

            local result = migration.status(driver)
            assert.are.equal(2, #result.executed)
        end)
    end)
end)
