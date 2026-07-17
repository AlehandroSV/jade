describe("SQLite Driver SQL Generation", function()
    local SQLite = require("jade.driver.sqlite")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")
    local Timestamp = require("jade.types.timestamp")
    local Schema = require("jade.schema")

    local driver
    local User

    before_each(function()
        driver = SQLite.new()
        User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
            email = String():unique(),
            active = Boolean():default(true),
            created_at = Timestamp():defaultNow(),
        })
        User:configure(driver)
    end)

    describe("mapType", function()
        it("maps string to TEXT", function()
            local col = String(120)
            assert.are.equal("TEXT", driver:mapType(col))
        end)

        it("maps string default length to TEXT", function()
            local col = String()
            assert.are.equal("TEXT", driver:mapType(col))
        end)

        it("maps integer", function()
            local col = Integer()
            assert.are.equal("INTEGER", driver:mapType(col))
        end)

        it("maps boolean to INTEGER", function()
            local col = Boolean()
            assert.are.equal("INTEGER", driver:mapType(col))
        end)

        it("maps timestamp to TEXT", function()
            local col = Timestamp()
            assert.are.equal("TEXT", driver:mapType(col))
        end)

        it("maps blob", function()
            local col = { type = "blob" }
            assert.are.equal("BLOB", driver:mapType(col))
        end)

        it("maps real", function()
            local col = { type = "real" }
            assert.are.equal("REAL", driver:mapType(col))
        end)

        it("maps json to TEXT", function()
            local col = { type = "json" }
            assert.are.equal("TEXT", driver:mapType(col))
        end)

        it("maps uuid to TEXT", function()
            local col = { type = "uuid" }
            assert.are.equal("TEXT", driver:mapType(col))
        end)

        it("maps unknown type to TEXT", function()
            local col = { type = "unknown" }
            assert.are.equal("TEXT", driver:mapType(col))
        end)
    end)

    describe("generateSelect", function()
        it("generates simple select", function()
            local q = User:where(User.active:eq(true))
            local sql, bindings = driver:generateSelect(q)
            assert.is_truth(string.find(sql, "SELECT"))
            assert.is_truth(string.find(sql, "FROM"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_truth(string.find(sql, "users"))
            assert.are.same({ true }, bindings)
        end)

        it("generates select with order and limit", function()
            local q = User:orderBy(User.name):limit(10)
            local sql, bindings = driver:generateSelect(q)
            assert.is_truth(string.find(sql, "SELECT"))
            assert.is_truth(string.find(sql, "ORDER BY"))
            assert.is_truth(string.find(sql, "LIMIT 10"))
        end)

        it("generates select with multiple wheres", function()
            local q = User:where(User.active:eq(true)):where(User.name:isNotNull())
            local sql, bindings = driver:generateSelect(q)
            assert.is_truth(string.find(sql, "SELECT"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_truth(string.find(sql, "AND"))
        end)

        it("generates select with offset", function()
            local q = User:limit(10):offset(5)
            local sql, bindings = driver:generateSelect(q)
            assert.is_truth(string.find(sql, "LIMIT 10"))
            assert.is_truth(string.find(sql, "OFFSET 5"))
        end)
    end)

    describe("generateInsert", function()
        it("generates insert", function()
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_falsy(string.find(sql, "RETURNING"))
            assert.are.equal(2, #bindings)
        end)
    end)

    describe("generateUpdate", function()
        it("generates update with where", function()
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateUpdate("users", { name = "New" }, where)
            assert.is_truth(string.find(sql, "UPDATE"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_truth(string.find(sql, "SET"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)
    end)

    describe("generateDelete", function()
        it("generates delete with where", function()
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateDelete("users", where)
            assert.is_truth(string.find(sql, "DELETE FROM"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.are.same({ 1 }, bindings)
        end)
    end)

    describe("dropTableCascade", function()
        it("returns false for SQLite", function()
            assert.is_false(driver:dropTableCascade())
        end)
    end)

    describe("supportsAutoIncrement", function()
        it("returns true for SQLite", function()
            assert.is_true(driver:supportsAutoIncrement())
        end)
    end)

    describe("quoteIdentifier", function()
        it("quotes identifier with backticks", function()
            assert.are.equal("`users`", driver:quoteIdentifier("users"))
        end)

        it("escapes backticks in identifier", function()
            assert.are.equal("`user``name`", driver:quoteIdentifier("user`name"))
        end)
    end)

    describe("Table DDL", function()
        it("generates CREATE TABLE with INTEGER PRIMARY KEY AUTOINCREMENT", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true, auto_increment = true })
            tbl:column("name", "string", { length = 120 })

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "CREATE TABLE"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_truth(string.find(sql, "INTEGER"))
            assert.is_truth(string.find(sql, "PRIMARY KEY"))
            assert.is_truth(string.find(sql, "AUTOINCREMENT"))
        end)

        it("generates CREATE TABLE without AUTOINCREMENT when not primary key", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true })
            tbl:column("name", "string", { length = 120 })

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "CREATE TABLE"))
            assert.is_truth(string.find(sql, "INTEGER"))
            assert.is_truth(string.find(sql, "PRIMARY KEY"))
            assert.is_falsy(string.find(sql, "AUTOINCREMENT"))
        end)

        it("generates CREATE TABLE with TEXT columns", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true })
            tbl:column("name", "string", { length = 120 })
            tbl:column("bio", "text")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "TEXT"))
        end)

        it("generates CREATE TABLE with BLOB column", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("files")
            tbl:column("id", "integer", { primary_key = true })
            tbl:column("data", "blob")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "BLOB"))
        end)

        it("generates CREATE TABLE with REAL column", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("measurements")
            tbl:column("id", "integer", { primary_key = true })
            tbl:column("value", "float")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "REAL"))
        end)
    end)
end)
