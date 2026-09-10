describe("Migration Tracker", function()
    local tracker = require("jade.migration.tracker")

    local migrations_table
    local executed_sql
    local mock_driver

    local function base_mapType(column_type)
        local map = {
            string = "TEXT",
            integer = "INTEGER",
            timestamp = "TEXT",
        }
        return map[column_type.type] or "TEXT"
    end

    before_each(function()
        migrations_table = {}
        executed_sql = {}
        mock_driver = {
            _driver_type = "sqlite",
            mapType = function(self, column_type)
                return base_mapType(column_type)
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
            execute = function(self, sql, bindings)
                executed_sql[#executed_sql + 1] = sql
                local function row_name()
                    if bindings and bindings[1] then
                        return bindings[1]
                    end
                    return sql:match("VALUES%s*%(%s*'([^']*)'") or sql:match("name%s*=%s*'([^']*)'")
                end
                if sql:match("CREATE TABLE") then
                    return {}
                elseif sql:match("ALTER TABLE") then
                    return {}
                elseif sql:match("SELECT jade_version") then
                    return {}
                elseif sql:match("INSERT INTO _jade_migrations") then
                    local name = row_name()
                    if name then
                        name = name:gsub("''", "'")
                    end
                    migrations_table[#migrations_table + 1] = { name = name }
                    return {}
                elseif sql:match("DELETE FROM _jade_migrations") then
                    local name = row_name()
                    if name then
                        name = name:gsub("''", "'")
                    end
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
                    return migrations_table
                end
                return {}
            end,
        }
    end)

    local function create_sqls()
        local sqls = {}
        for _, sql in ipairs(executed_sql) do
            if sql:match("CREATE TABLE") then
                sqls[#sqls + 1] = sql
            end
        end
        return sqls
    end

    it("creates tracker table", function()
        tracker.createTrackerTable(mock_driver)
        assert.is_true(#create_sqls() >= 1)
    end)

    it("emits CREATE TABLE IF NOT EXISTS without PostgreSQL-only DDL", function()
        tracker.createTrackerTable(mock_driver)
        local sql = create_sqls()[1]
        assert.is_truth(sql)
        assert.is_truth(sql:match("CREATE TABLE IF NOT EXISTS"))
        assert.is_truth(sql:match("_jade_migrations"))
        assert.is_falsy(sql:match("SERIAL"))
        assert.is_falsy(sql:match("TIMESTAMPTZ"))
        assert.is_falsy(sql:match("NOW%("))
        assert.is_truth(sql:match("CURRENT_TIMESTAMP"))
    end)

    it("uses driver mapType for SQLite", function()
        local SQLite = require("jade.driver.sqlite")
        local driver = SQLite.new()
        local sqls = {}
        driver.execute = function(_, sql)
            sqls[#sqls + 1] = sql
            return {}
        end
        tracker.createTrackerTable(driver)
        local sql = sqls[1]
        assert.is_truth(sql)
        assert.is_truth(sql:match("CREATE TABLE IF NOT EXISTS"))
        assert.is_truth(sql:match("INTEGER"))
        assert.is_truth(sql:match("PRIMARY KEY"))
        assert.is_truth(sql:match("AUTOINCREMENT"))
        assert.is_truth(sql:match("TEXT"))
        assert.is_falsy(sql:match("SERIAL"))
        assert.is_falsy(sql:match("TIMESTAMPTZ"))
        assert.is_falsy(sql:match("information_schema"))
    end)

    it("uses driver mapType for PostgreSQL", function()
        local PostgreSQL = require("jade.driver.postgresql")
        local driver = PostgreSQL.new()
        local sqls = {}
        driver.execute = function(_, sql)
            sqls[#sqls + 1] = sql
            return {}
        end
        tracker.createTrackerTable(driver)
        local sql = sqls[1]
        assert.is_truth(sql)
        assert.is_truth(sql:match("CREATE TABLE IF NOT EXISTS"))
        assert.is_truth(sql:match("SERIAL"))
        assert.is_truth(sql:match("PRIMARY KEY"))
        assert.is_truth(sql:match("VARCHAR%(255%)"))
        assert.is_truth(sql:match("TIMESTAMPTZ"))
        assert.is_truth(sql:match("CURRENT_TIMESTAMP"))
        assert.is_falsy(sql:match("AUTOINCREMENT"))
        assert.is_falsy(sql:match("information_schema"))
    end)

    it("uses driver mapType for MySQL", function()
        local MySQL = require("jade.driver.mysql")
        local driver = MySQL.new()
        local sqls = {}
        driver.execute = function(_, sql)
            sqls[#sqls + 1] = sql
            return {}
        end
        tracker.createTrackerTable(driver)
        local sql = sqls[1]
        assert.is_truth(sql)
        assert.is_truth(sql:match("CREATE TABLE IF NOT EXISTS"))
        assert.is_truth(sql:match("INTEGER"))
        assert.is_truth(sql:match("PRIMARY KEY"))
        assert.is_truth(sql:match("AUTO_INCREMENT"))
        assert.is_truth(sql:match("VARCHAR%(255%)"))
        assert.is_truth(sql:match("TIMESTAMP"))
        assert.is_truth(sql:match("CURRENT_TIMESTAMP"))
        assert.is_falsy(sql:match("TIMESTAMPTZ"))
        assert.is_falsy(sql:match("NOW%("))
        assert.is_falsy(sql:match("SERIAL"))
    end)

    it("does not query information_schema", function()
        tracker.createTrackerTable(mock_driver)
        for _, sql in ipairs(executed_sql) do
            assert.is_falsy(sql:match("information_schema"))
        end
    end)

    it("adds jade_version when missing from existing tracker table", function()
        mock_driver.execute = function(self, sql, bindings)
            executed_sql[#executed_sql + 1] = sql
            if sql:match("CREATE TABLE") then
                return {}
            elseif sql:match("SELECT jade_version") then
                error("no such column: jade_version")
            elseif sql:match("ALTER TABLE") then
                return {}
            elseif sql:match("INSERT INTO _jade_migrations") then
                migrations_table[#migrations_table + 1] = { name = bindings[1] }
                return {}
            elseif sql:match("SELECT name FROM _jade_migrations") then
                return migrations_table
            end
            return {}
        end

        tracker.createTrackerTable(mock_driver)
        local altered = false
        for _, sql in ipairs(executed_sql) do
            if sql:match("ALTER TABLE") and sql:match("jade_version") then
                altered = true
            end
        end
        assert.is_true(altered)
    end)

    it("records migration", function()
        tracker.recordMigration(mock_driver, "20260715120000_create_users.lua")
        assert.are.equal(1, #migrations_table)
        assert.are.equal("20260715120000_create_users.lua", migrations_table[1].name)
    end)

    it("gets applied migrations", function()
        tracker.recordMigration(mock_driver, "20260715120000_create_users.lua")
        tracker.recordMigration(mock_driver, "20260715120001_create_posts.lua")
        local applied = tracker.getAppliedMigrations(mock_driver)
        assert.is_true(applied["20260715120000_create_users.lua"])
        assert.is_true(applied["20260715120001_create_posts.lua"])
    end)

    it("removes migration", function()
        tracker.recordMigration(mock_driver, "20260715120000_create_users.lua")
        tracker.removeMigration(mock_driver, "20260715120000_create_users.lua")
        local applied = tracker.getAppliedMigrations(mock_driver)
        assert.is_falsy(applied["20260715120000_create_users.lua"])
    end)

    it("gets last applied", function()
        tracker.recordMigration(mock_driver, "20260715120000_create_users.lua")
        tracker.recordMigration(mock_driver, "20260715120001_create_posts.lua")
        tracker.recordMigration(mock_driver, "20260715120002_create_comments.lua")
        local last = tracker.getLastApplied(mock_driver, 2)
        assert.are.equal(2, #last)
        assert.are.equal("20260715120002_create_comments.lua", last[1])
        assert.are.equal("20260715120001_create_posts.lua", last[2])
    end)

    describe("SQLite in-memory integration", function()
        local SQLite = require("jade.driver.sqlite")

        local function connect_sqlite()
            local driver = SQLite.new()
            driver:connect({ database = ":memory:" })
            return driver
        end

        local function has_column(driver, name)
            local res = driver:execute("PRAGMA table_info(_jade_migrations)")
            local found = false
            if type(res) == "userdata" and res.fetch then
                local row = res:fetch({}, "a")
                while row do
                    if row.name == name then found = true end
                    row = res:fetch({}, "a")
                end
                if res.close then
                    pcall(function() res:close() end)
                end
            elseif type(res) == "table" then
                for _, row in ipairs(res) do
                    if row.name == name then found = true end
                end
            end
            return found
        end

        it("creates tracker table on SQLite", function()
            local driver = connect_sqlite()
            tracker.createTrackerTable(driver)
            assert.is_true(has_column(driver, "id"))
            assert.is_true(has_column(driver, "name"))
            assert.is_true(has_column(driver, "jade_version"))
            assert.is_true(has_column(driver, "applied_at"))
            driver:disconnect()
        end)

        it("is idempotent on SQLite", function()
            local driver = connect_sqlite()
            tracker.createTrackerTable(driver)
            tracker.createTrackerTable(driver)
            assert.is_true(has_column(driver, "name"))
            driver:disconnect()
        end)

        it("upgrades legacy table missing jade_version", function()
            local driver = connect_sqlite()
            driver:execute([[
                CREATE TABLE _jade_migrations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    applied_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ]])
            assert.is_false(has_column(driver, "jade_version"))
            tracker.createTrackerTable(driver)
            assert.is_true(has_column(driver, "jade_version"))
            driver:disconnect()
        end)

        it("records, lists and removes migrations on SQLite", function()
            local driver = connect_sqlite()
            tracker.createTrackerTable(driver)
            tracker.recordMigration(driver, "20260715120000_create_users.lua")
            tracker.recordMigration(driver, "20260715120001_create_posts.lua")

            local applied = tracker.getAppliedMigrations(driver)
            assert.is_true(applied["20260715120000_create_users.lua"])
            assert.is_true(applied["20260715120001_create_posts.lua"])

            local last = tracker.getLastApplied(driver, 1)
            assert.are.equal(1, #last)
            assert.are.equal("20260715120001_create_posts.lua", last[1])

            tracker.removeMigration(driver, "20260715120000_create_users.lua")
            applied = tracker.getAppliedMigrations(driver)
            assert.is_falsy(applied["20260715120000_create_users.lua"])
            assert.is_true(applied["20260715120001_create_posts.lua"])
            driver:disconnect()
        end)

        it("migration.init works on SQLite", function()
            local driver = connect_sqlite()
            local migration = require("jade.migration")
            migration.init(driver)
            assert.is_true(has_column(driver, "name"))
            driver:disconnect()
        end)
    end)
end)
