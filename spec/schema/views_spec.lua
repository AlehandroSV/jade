describe("Database Views", function()
    local Schema = require("jade.schema")
    local Quoting = require("jade.util.quoting")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")
    local Query = require("jade.query")

    describe("Schema.createView()", function()
        it("generates CREATE VIEW SQL", function()
            local captured_sql = nil

            local mock_driver = {
                generateSelect = function(self, query)
                    return "SELECT id, name FROM users WHERE active = ?", { true }
                end,
                execute = function(self, sql, bindings)
                    captured_sql = sql
                end,
            }

            local User = Entity.new("users", {
                id = Integer():primaryKey(),
                name = String(120),
                active = Boolean(),
            })
            User:configure({
                generateSelect = function(self, query)
                    return "SELECT id, name FROM users WHERE active = ?", { true }
                end,
                execute = function(self, sql, bindings) return {} end,
            })

            local query = User:where(User.active:eq(true)):select("id", "name")
            Schema.createView(mock_driver, "active_users", query)

            assert.is_not_nil(captured_sql)
            assert.is_truth(string.find(captured_sql, "CREATE VIEW"))
            assert.is_truth(string.find(captured_sql, "active_users"))
            assert.is_truth(string.find(captured_sql, "SELECT"))
        end)

        it("returns true on success", function()
            local mock_driver = {
                execute = function(self, sql, bindings) end,
            }

            local User = Entity.new("users", {
                id = Integer():primaryKey(),
            })
            User:configure({
                generateSelect = function(self, query)
                    return "SELECT * FROM users", {}
                end,
                execute = function(self, sql, bindings) return {} end,
            })

            local query = User:select("*")
            local result = Schema.createView(mock_driver, "test_view", query)
            assert.is_true(result)
        end)
    end)

    describe("Schema.View()", function()
        it("returns a query-like object", function()
            local mock_driver = {
                execute = function(self, sql, bindings)
                    return { { id = 1, name = "John" } }
                end,
            }

            local view = Schema.View(mock_driver, "active_users")
            assert.is_not_nil(view)
            assert.is_not_nil(view.toSQL)
            assert.is_not_nil(view.get)
        end)

        it("generates SELECT * FROM view SQL", function()
            local mock_driver = {
                execute = function(self, sql, bindings) return {} end,
            }

            local view = Schema.View(mock_driver, "active_users")
            local sql, bindings = view:toSQL()

            assert.is_not_nil(sql)
            assert.is_truth(string.find(sql, "SELECT"))
            assert.is_truth(string.find(sql, "active_users"))
        end)

        it("executes query on get()", function()
            local mock_driver = {
                execute = function(self, sql, bindings)
                    return { { id = 1, name = "John" } }
                end,
            }

            local view = Schema.View(mock_driver, "active_users")
            local result = view:get()

            assert.is_not_nil(result)
            assert.are.equal(1, #result)
            assert.are.equal("John", result[1].name)
        end)
    end)

    describe("Schema.dropView()", function()
        it("generates DROP VIEW SQL", function()
            local captured_sql = nil

            local mock_driver = {
                execute = function(self, sql, bindings)
                    captured_sql = sql
                end,
            }

            Schema.dropView(mock_driver, "active_users")

            assert.is_not_nil(captured_sql)
            assert.is_truth(string.find(captured_sql, "DROP VIEW"))
            assert.is_truth(string.find(captured_sql, "active_users"))
        end)

        it("returns true on success", function()
            local mock_driver = {
                execute = function(self, sql, bindings) end,
            }

            local result = Schema.dropView(mock_driver, "test_view")
            assert.is_true(result)
        end)
    end)

    describe("Integration", function()
        it("creates view and queries it", function()
            local captured_sql = nil

            local mock_driver = {
                generateSelect = function(self, query)
                    return "SELECT id, name FROM users WHERE active = ?", { true }
                end,
                execute = function(self, sql, bindings)
                    if not captured_sql then
                        captured_sql = sql
                    end
                    return { { id = 1, name = "John" } }
                end,
            }

            local User = Entity.new("users", {
                id = Integer():primaryKey(),
                name = String(120),
                active = Boolean(),
            })
            User:configure(mock_driver)

            local query = User:where(User.active:eq(true)):select("id", "name")
            Schema.createView(mock_driver, "active_users", query)

            local view = Schema.View(mock_driver, "active_users")
            local result = view:get()

            assert.is_not_nil(result)
            assert.are.equal(1, #result)
            assert.are.equal("John", result[1].name)
        end)
    end)
end)
