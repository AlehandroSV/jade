describe("PostgreSQL Driver SQL Generation", function()
    local PostgreSQL = require("jade.driver.postgresql")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")
    local Timestamp = require("jade.types.timestamp")

    local driver
    local User

    before_each(function()
        driver = PostgreSQL.new()
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
        it("maps string with length", function()
            local col = String(120)
            assert.are.equal("VARCHAR(120)", driver:mapType(col))
        end)

        it("maps string default length", function()
            local col = String()
            assert.are.equal("VARCHAR(255)", driver:mapType(col))
        end)

        it("maps integer", function()
            local col = Integer()
            assert.are.equal("INTEGER", driver:mapType(col))
        end)

        it("maps boolean", function()
            local col = Boolean()
            assert.are.equal("BOOLEAN", driver:mapType(col))
        end)

        it("maps timestamp", function()
            local col = Timestamp()
            assert.are.equal("TIMESTAMPTZ", driver:mapType(col))
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
    end)

    describe("generateInsert", function()
        it("generates insert with return", function()
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_truth(string.find(sql, "RETURNING *"))
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
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_truth(string.find(sql, "RETURNING *"))
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
            assert.is_truth(string.find(sql, "RETURNING"))
        end)
    end)
end)
