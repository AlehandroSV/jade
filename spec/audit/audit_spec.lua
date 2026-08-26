describe("Audit", function()
    local Audit = require("jade.audit")

    -- Mock entity
    local function makeMockEntity(table_name)
        local entity = {
            _table = table_name or "users",
            _driver = nil,
            _callbacks = {
                beforeCreate = {},
                beforeUpdate = {},
                beforeDelete = {},
                afterCreate = {},
                afterUpdate = {},
                afterDelete = {},
            },
        }

        function entity:beforeCreate(fn)
            table.insert(self._callbacks.beforeCreate, fn)
        end

        function entity:beforeUpdate(fn)
            table.insert(self._callbacks.beforeUpdate, fn)
        end

        function entity:beforeDelete(fn)
            table.insert(self._callbacks.beforeDelete, fn)
        end

        function entity:afterCreate(fn)
            table.insert(self._callbacks.afterCreate, fn)
        end

        function entity:afterUpdate(fn)
            table.insert(self._callbacks.afterUpdate, fn)
        end

        function entity:afterDelete(fn)
            table.insert(self._callbacks.afterDelete, fn)
        end

        return entity
    end

    -- Mock driver
    local function makeMockDriver()
        local executed_sql = {}
        local driver = {
            _executed_sql = executed_sql,
        }

        function driver:execute(sql, bindings)
            table.insert(executed_sql, { sql = sql, bindings = bindings })
            return { rows = {}, affected = 1 }
        end

        return driver
    end

    before_each(function()
        Audit.clear()
    end)

    ----------------------------------------------------------------
    -- Setup
    ----------------------------------------------------------------

    describe("setup", function()
        it("registers audit callbacks for entity", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity)
            assert.are.equal(1, #entity._callbacks.beforeCreate)
            assert.are.equal(1, #entity._callbacks.beforeUpdate)
            assert.are.equal(1, #entity._callbacks.beforeDelete)
            assert.are.equal(1, #entity._callbacks.afterCreate)
            assert.are.equal(1, #entity._callbacks.afterUpdate)
            assert.are.equal(1, #entity._callbacks.afterDelete)
        end)

        it("accepts ignored fields option", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity, { ignore = { "password", "secret" } })
            -- Should not error
            assert.is_true(true)
        end)

        it("returns true on success", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local result = Audit.setup(entity)
            assert.is_true(result)
        end)
    end)

    ----------------------------------------------------------------
    -- Callback execution
    ----------------------------------------------------------------

    describe("callbacks", function()
        it("sets _audit_action to create in beforeCreate", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity)
            local data = { name = "John" }
            entity._callbacks.beforeCreate[1](data)
            assert.are.equal("create", data._audit_action)
        end)

        it("sets _audit_action to update in beforeUpdate", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity)
            local data = { name = "John" }
            entity._callbacks.beforeUpdate[1](data)
            assert.are.equal("update", data._audit_action)
        end)

        it("sets _audit_action to delete in beforeDelete", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity)
            local data = { name = "John" }
            entity._callbacks.beforeDelete[1](data)
            assert.are.equal("delete", data._audit_action)
        end)
    end)

    ----------------------------------------------------------------
    -- Audit logging
    ----------------------------------------------------------------

    describe("_log", function()
        it("creates audit log entry on create", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver
            Audit.setup(entity)

            local instance = { _data = { id = 1, name = "John" } }
            Audit._log(entity, instance, "create", nil, nil)

            assert.are.equal(2, #driver._executed_sql) -- CREATE TABLE + INSERT
            local insert_sql = driver._executed_sql[2].sql
            assert.is_true(insert_sql:find("INSERT INTO") ~= nil)
            assert.is_true(insert_sql:find("jade_audit_logs") ~= nil)
        end)

        it("creates audit log entry on update with changes", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver
            Audit.setup(entity)

            local instance = { _data = { id = 1, name = "John" } }
            local changes = {
                name = { old = "John", new = "Jane" },
            }
            Audit._log(entity, instance, "update", changes, nil)

            assert.are.equal(2, #driver._executed_sql)
            local insert_sql = driver._executed_sql[2].sql
            assert.is_true(insert_sql:find("INSERT INTO") ~= nil)
        end)

        it("filters ignored fields from changes", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver
            Audit.setup(entity, { ignore = { "password" } })

            local instance = { _data = { id = 1 } }
            local changes = {
                name = { old = "John", new = "Jane" },
                password = { old = "old", new = "new" },
            }
            Audit._log(entity, instance, "update", changes, nil)

            -- Should still log, but password should be filtered
            assert.are.equal(2, #driver._executed_sql)
        end)

        it("does not log when no changes after filtering", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver
            Audit.setup(entity, { ignore = { "name" } })

            local instance = { _data = { id = 1 } }
            local changes = {
                name = { old = "John", new = "Jane" },
            }
            Audit._log(entity, instance, "update", changes, nil)

            -- Should only have CREATE TABLE, no INSERT
            assert.are.equal(1, #driver._executed_sql)
        end)

        it("handles nil instance gracefully", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver
            Audit.setup(entity)

            Audit._log(entity, nil, "delete", nil, nil)
            assert.are.equal(2, #driver._executed_sql)
        end)

        it("does nothing when entity not configured", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            local driver = makeMockDriver()
            entity._driver = driver

            -- Don't call setup
            Audit._log(entity, { _data = { id = 1 } }, "create", nil, nil)
            assert.are.equal(0, #driver._executed_sql)
        end)

        it("does nothing when driver is nil", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            entity._driver = nil
            Audit.setup(entity)

            -- Should not error
            Audit._log(entity, { _data = { id = 1 } }, "create", nil, nil)
        end)
    end)

    ----------------------------------------------------------------
    -- Table creation
    ----------------------------------------------------------------

    describe("_ensureTable", function()
        it("creates audit logs table", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit._ensureTable(driver)
            assert.are.equal(1, #driver._executed_sql)
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("CREATE TABLE IF NOT EXISTS") ~= nil)
            assert.is_true(sql:find("jade_audit_logs") ~= nil)
        end)

        it("uses appropriate SQL types for PostgreSQL", function()
            Audit.clear()
            local driver = makeMockDriver()
            -- Mock PostgreSQL driver
            setmetatable(driver, { __tostring = function() return "PostgreSQL" end })
            Audit._ensureTable(driver)
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("SERIAL PRIMARY KEY") ~= nil)
            assert.is_true(sql:find("TIMESTAMPTZ") ~= nil)
        end)

        it("uses appropriate SQL types for MySQL", function()
            Audit.clear()
            local driver = makeMockDriver()
            setmetatable(driver, { __tostring = function() return "MySQL" end })
            Audit._ensureTable(driver)
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("AUTO_INCREMENT") ~= nil)
            assert.is_true(sql:find("TIMESTAMP") ~= nil)
        end)

        it("uses SQLite types by default", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit._ensureTable(driver)
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("INTEGER PRIMARY KEY") ~= nil)
            assert.is_true(sql:find("TEXT") ~= nil)
        end)
    end)

    ----------------------------------------------------------------
    -- Query audit logs
    ----------------------------------------------------------------

    describe("query", function()
        it("queries all audit logs", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit.query(driver)
            assert.are.equal(1, #driver._executed_sql)
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("SELECT * FROM", 1, true) ~= nil)
            assert.is_true(sql:find("ORDER BY created_at DESC") ~= nil)
        end)

        it("filters by table_name", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit.query(driver, { table_name = "users" })
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("table_name = ?") ~= nil)
            assert.are.equal("users", driver._executed_sql[1].bindings[1])
        end)

        it("filters by record_id", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit.query(driver, { record_id = 42 })
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("record_id = ?") ~= nil)
            assert.are.equal("42", driver._executed_sql[1].bindings[1])
        end)

        it("filters by action", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit.query(driver, { action = "create" })
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("action = ?") ~= nil)
            assert.are.equal("create", driver._executed_sql[1].bindings[1])
        end)

        it("combines multiple filters", function()
            Audit.clear()
            local driver = makeMockDriver()
            Audit.query(driver, { table_name = "users", action = "update" })
            local sql = driver._executed_sql[1].sql
            assert.is_true(sql:find("table_name = ?") ~= nil)
            assert.is_true(sql:find("action = ?") ~= nil)
            assert.is_true(sql:find(" AND ") ~= nil)
        end)
    end)

    ----------------------------------------------------------------
    -- State management
    ----------------------------------------------------------------

    describe("clear", function()
        it("clears audit configuration", function()
            Audit.clear()
            local entity = makeMockEntity("users")
            Audit.setup(entity)
            Audit.clear()
            -- After clear, _log should do nothing
            local driver = makeMockDriver()
            entity._driver = driver
            Audit._log(entity, { _data = { id = 1 } }, "create", nil, nil)
            assert.are.equal(0, #driver._executed_sql)
        end)
    end)
end)
