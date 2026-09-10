-- Tests for per-migration tracker persistence (#176)
-- Tracker must record each successful migration immediately (same tx when
-- possible), so a crash mid-batch cannot desync tracker vs applied DDL.

describe("Migration tracker per-migration (#176)", function()
    local tracker = require("jade.migration.tracker")
    local M = require("jade.migration")

    local original_file = M.file
    local original_runner = M.runner

    local function restore()
        M.file = original_file
        M.runner = original_runner
    end

    local function mock_driver()
        local migrations_table = {}
        local driver = {
            _migrations = migrations_table,
            _in_tx = false,
            _tx_depth = 0,
            _driver_type = "sqlite",
            mapType = function(_, column_type)
                local t = column_type
                if type(t) == "table" then
                    t = t.type
                end
                if t == "integer" then
                    return "INTEGER"
                elseif t == "timestamp" then
                    return "TEXT"
                end
                return "TEXT"
            end,
            supportsAutoIncrement = function()
                return true
            end,
            autoIncrementKeyword = function()
                return "AUTOINCREMENT"
            end,
            quoteIdentifier = function(_, name)
                return "`" .. name:gsub("`", "``") .. "`"
            end,
        }

        function driver:transaction(fn)
            self._in_tx = true
            self._tx_depth = self._tx_depth + 1
            local ok, err = pcall(fn)
            self._tx_depth = self._tx_depth - 1
            if self._tx_depth == 0 then
                self._in_tx = false
            end
            if not ok then
                error(err, 0)
            end
            return true
        end

        -- Support both bound params (legacy) and inline escaped values (#177).
        local function extract_name(sql, bindings)
            if bindings and bindings[1] then
                return bindings[1]
            end
            -- #177 inlines escaped literals: VALUES ('name', '...') / name = 'name'
            local from_values = sql:match("VALUES%s*%(%s*'([^']*)'")
            if from_values then
                return from_values:gsub("''", "'")
            end
            local from_eq = sql:match("name%s*=%s*'([^']*)'")
            if from_eq then
                return from_eq:gsub("''", "'")
            end
            return nil
        end

        function driver:execute(sql, bindings)
            if sql:match("CREATE TABLE") then
                return {}
            elseif sql:match("SELECT jade_version") then
                -- #177 upgrade probe: empty result means column exists (no ALTER)
                return {}
            elseif sql:match("ALTER TABLE") then
                return {}
            elseif sql:match("INSERT INTO _jade_migrations") then
                migrations_table[#migrations_table + 1] = {
                    name = extract_name(sql, bindings),
                    in_tx = self._in_tx,
                }
                return {}
            elseif sql:match("DELETE FROM _jade_migrations") then
                local name = extract_name(sql, bindings)
                for i, row in ipairs(migrations_table) do
                    if row.name == name then
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

    local function mock_file(names)
        return {
            listFiles = function()
                local files = {}
                for _, name in ipairs(names) do
                    files[#files + 1] = { name = name, path = "migrations/" .. name }
                end
                return files
            end,
            load = function(path)
                return { name = path:match("([^/]+)$") }
            end,
        }
    end

    local function mock_runner(opts)
        opts = opts or {}
        local fail_migration = opts.fail_migration
        local on_start = opts.on_start
        return {
            run = function(driver, migration, direction, run_opts)
                if on_start then
                    on_start(driver, migration)
                end
                if fail_migration and migration.name == fail_migration then
                    error("Migration failed: " .. migration.name)
                end
                if run_opts and run_opts.after then
                    run_opts.after(driver)
                end
                return true
            end,
        }
    end

    it("records first migration before second starts", function()
        local driver = mock_driver()
        local observed_before_second = nil

        M.file = mock_file({ "001_create_users", "002_add_email" })
        M.runner = mock_runner({
            on_start = function(d, migration)
                if migration.name == "002_add_email" then
                    observed_before_second = tracker.getAppliedMigrations(d)["001_create_users"]
                end
            end,
        })

        local ok, err = pcall(function()
            M.migrate(driver)
        end)
        restore()

        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_true(observed_before_second)
    end)

    it("keeps first recorded when second migration fails (crash mid-batch)", function()
        local driver = mock_driver()
        M.file = mock_file({ "001_create_users", "002_add_email" })
        M.runner = mock_runner({ fail_migration = "002_add_email" })

        local ok, err = pcall(function()
            M.migrate(driver)
        end)
        restore()

        assert.is_falsy(ok)
        assert.is_truthy(tostring(err):find("002_add_email"))

        local applied = tracker.getAppliedMigrations(driver)
        assert.is_true(applied["001_create_users"])
        assert.is_falsy(applied["002_add_email"])
    end)

    it("records tracker inside the same transaction as the migration", function()
        local driver = mock_driver()
        -- Use the real runner so after() is wrapped in driver:transaction
        M.file = {
            listFiles = function()
                return {
                    { name = "001_create_users", path = "migrations/001_create_users" },
                }
            end,
            load = function()
                return { up = function() end, down = function() end }
            end,
        }

        local ok, err = pcall(function()
            M.migrate(driver)
        end)
        restore()

        assert.is_true(ok)
        assert.is_nil(err)
        assert.are.equal(1, #driver._migrations)
        assert.are.equal("001_create_users", driver._migrations[1].name)
        assert.is_true(driver._migrations[1].in_tx)
    end)

    it("removes tracker immediately per successful rollback", function()
        local driver = mock_driver()
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")

        local observed_before_second = nil
        M.file = {
            load = function(path)
                return { name = path:match("([^/]+)$") }
            end,
        }
        M.runner = mock_runner({
            on_start = function(d, migration)
                -- getLastApplied DESC: 002 first, then 001
                if migration.name == "001_create_users" then
                    observed_before_second = tracker.getAppliedMigrations(d)["002_add_email"]
                end
            end,
        })

        local ok, err = pcall(function()
            M.rollback(driver, 2)
        end)
        restore()

        assert.is_true(ok)
        assert.is_nil(err)
        assert.is_falsy(observed_before_second)
        local applied = tracker.getAppliedMigrations(driver)
        assert.is_falsy(applied["001_create_users"])
        assert.is_falsy(applied["002_add_email"])
    end)

    it("keeps earlier rollback removals when a later rollback fails", function()
        local driver = mock_driver()
        tracker.recordMigration(driver, "001_create_users")
        tracker.recordMigration(driver, "002_add_email")
        tracker.recordMigration(driver, "003_add_bio")

        M.file = {
            load = function(path)
                return { name = path:match("([^/]+)$") }
            end,
        }
        M.runner = mock_runner({ fail_migration = "001_create_users" })

        local ok, err = pcall(function()
            M.rollback(driver, 3)
        end)
        restore()

        assert.is_falsy(ok)
        assert.is_truthy(tostring(err):find("001_create_users"))

        local applied = tracker.getAppliedMigrations(driver)
        assert.is_true(applied["001_create_users"])
        assert.is_falsy(applied["002_add_email"])
        assert.is_falsy(applied["003_add_bio"])
    end)
end)
