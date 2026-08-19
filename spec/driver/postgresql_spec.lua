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

        it("generates select with limit and offset", function()
            local q = User:limit(10):offset(5)
            local sql, bindings = driver:generateSelect(q)
            assert.is_truth(string.find(sql, "LIMIT 10"))
            assert.is_truth(string.find(sql, "OFFSET 5"))
        end)

        it("does not generate OFFSET without LIMIT", function()
            local q = User:offset(5)
            local sql, bindings = driver:generateSelect(q)
            assert.is_falsy(string.find(sql, "OFFSET"))
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

    describe("SSL Configuration", function()
        it("stores ssl option when enabled", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
                ssl = true,
            })
            assert.is_true(pg._config.ssl)
        end)

        it("defaults ssl to false", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
            })
            assert.is_false(pg._config.ssl)
        end)

        it("stores ssl_verify option", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
                ssl = true,
                ssl_verify = true,
            })
            assert.is_true(pg._config.ssl_verify)
        end)

        it("stores ssl_ca certificate path", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
                ssl = true,
                ssl_ca = "/path/to/ca.pem",
            })
            assert.are.equal("/path/to/ca.pem", pg._config.ssl_ca)
        end)

        it("stores ssl_cert certificate path", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
                ssl = true,
                ssl_cert = "/path/to/cert.pem",
            })
            assert.are.equal("/path/to/cert.pem", pg._config.ssl_cert)
        end)

        it("stores ssl_key key path", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "localhost",
                database = "test",
                user = "test",
                ssl = true,
                ssl_key = "/path/to/key.pem",
            })
            assert.are.equal("/path/to/key.pem", pg._config.ssl_key)
        end)

        it("stores all SSL options together", function()
            local pg = PostgreSQL.new()
            pg:connect({
                host = "db.example.com",
                port = 5432,
                database = "myapp",
                user = "app",
                password = "secret",
                ssl = true,
                ssl_verify = true,
                ssl_ca = "/etc/ssl/ca.pem",
                ssl_cert = "/etc/ssl/cert.pem",
                ssl_key = "/etc/ssl/key.pem",
            })
            assert.is_true(pg._config.ssl)
            assert.is_true(pg._config.ssl_verify)
            assert.are.equal("/etc/ssl/ca.pem", pg._config.ssl_ca)
            assert.are.equal("/etc/ssl/cert.pem", pg._config.ssl_cert)
            assert.are.equal("/etc/ssl/key.pem", pg._config.ssl_key)
        end)
    end)
end)
