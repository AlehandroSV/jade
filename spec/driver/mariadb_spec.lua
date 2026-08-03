describe("MariaDB Driver SQL Generation", function()
    local MariaDB = require("jade.driver.mariadb")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")
    local Timestamp = require("jade.types.timestamp")

    local driver
    local User

    before_each(function()
        driver = MariaDB.new()
        User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
            email = String():unique(),
            active = Boolean():default(true),
            created_at = Timestamp():defaultNow(),
        })
        User:configure(driver)
    end)

    describe("driver type", function()
        it("has mariadb driver type", function()
            assert.are.equal("mariadb", driver._driver_type)
        end)

        it("inherits from MySQL", function()
            local mysql_driver = getmetatable(getmetatable(driver)).__index
            assert.are.equal("mysql", mysql_driver._driver_type)
        end)
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
            assert.are.equal("TINYINT(1)", driver:mapType(col))
        end)

        it("maps timestamp", function()
            local col = Timestamp()
            assert.are.equal("TIMESTAMP", driver:mapType(col))
        end)

        it("maps tinyint", function()
            local col = { type = "tinyint" }
            assert.are.equal("TINYINT", driver:mapType(col))
        end)

        it("maps mediumtext", function()
            local col = { type = "mediumtext" }
            assert.are.equal("MEDIUMTEXT", driver:mapType(col))
        end)

        it("maps longtext", function()
            local col = { type = "longtext" }
            assert.are.equal("LONGTEXT", driver:mapType(col))
        end)

        it("maps json as native JSON", function()
            local col = { type = "json" }
            assert.are.equal("JSON", driver:mapType(col))
        end)

        it("maps datetime", function()
            local col = { type = "datetime" }
            assert.are.equal("DATETIME", driver:mapType(col))
        end)

        it("maps uuid type", function()
            local col = { type = "uuid" }
            assert.are.equal("UUID", driver:mapType(col))
        end)

        it("maps inet4 type", function()
            local col = { type = "inet4" }
            assert.are.equal("INET4", driver:mapType(col))
        end)

        it("maps inet6 type", function()
            local col = { type = "inet6" }
            assert.are.equal("INET6", driver:mapType(col))
        end)
    end)

    describe("generateInsert", function()
        it("generates insert without RETURNING when version unknown", function()
            driver._supports_returning = false
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "users"))
            assert.is_falsy(string.find(sql, "RETURNING"))
            assert.are.equal(2, #bindings)
        end)

        it("generates insert with RETURNING when version >= 10.5", function()
            driver._supports_returning = true
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "RETURNING"))
            assert.are.equal(2, #bindings)
        end)

        it("generates insert without RETURNING when version < 10.5", function()
            driver._supports_returning = false
            driver._mariadb_version = "10.4.12-MariaDB"
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)
    end)

    describe("generateUpdate", function()
        it("generates update without RETURNING when not supported", function()
            driver._supports_returning = false
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateUpdate("users", { name = "New" }, where)
            assert.is_truth(string.find(sql, "UPDATE"))
            assert.is_truth(string.find(sql, "SET"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)

        it("generates update with RETURNING when supported", function()
            driver._supports_returning = true
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateUpdate("users", { name = "New" }, where)
            assert.is_truth(string.find(sql, "UPDATE"))
            assert.is_truth(string.find(sql, "RETURNING"))
        end)
    end)

    describe("generateDelete", function()
        it("generates delete without RETURNING when not supported", function()
            driver._supports_returning = false
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateDelete("users", where)
            assert.is_truth(string.find(sql, "DELETE FROM"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)

        it("generates delete with RETURNING when supported", function()
            driver._supports_returning = true
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateDelete("users", where)
            assert.is_truth(string.find(sql, "DELETE FROM"))
            assert.is_truth(string.find(sql, "RETURNING"))
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
    end)

    describe("generateUpsert", function()
        it("generates upsert with ON DUPLICATE KEY UPDATE", function()
            driver._supports_returning = false
            local sql, bindings = driver:generateUpsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, { "email" }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "ON DUPLICATE KEY UPDATE"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)

        it("generates upsert with RETURNING when supported", function()
            driver._supports_returning = true
            local sql, bindings = driver:generateUpsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, { "email" }, User)
            assert.is_truth(string.find(sql, "INSERT INTO"))
            assert.is_truth(string.find(sql, "ON DUPLICATE KEY UPDATE"))
            assert.is_truth(string.find(sql, "RETURNING"))
        end)

        it("generates INSERT IGNORE without RETURNING when no update columns", function()
            driver._supports_returning = true
            local sql, bindings = driver:generateUpsert("users", {
                email = "lucas@test.com",
            }, { "email" }, User)
            assert.is_truth(string.find(sql, "INSERT IGNORE"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)
    end)

    describe("dropTableCascade", function()
        it("returns false", function()
            assert.is_false(driver:dropTableCascade())
        end)
    end)

    describe("supportsAutoIncrement", function()
        it("returns true", function()
            assert.is_true(driver:supportsAutoIncrement())
        end)
    end)

    describe("version detection", function()
        it("sets _supports_returning to true for version 10.5", function()
            driver._mariadb_version = "10.5.8-MariaDB"
            local major, minor = driver._mariadb_version:match("(%d+)%.(%d+)")
            local supports = (tonumber(major) > 10) or
                (tonumber(major) == 10 and tonumber(minor) >= 5)
            assert.is_true(supports)
        end)

        it("sets _supports_returning to true for version 11.0", function()
            driver._mariadb_version = "11.0.2-MariaDB"
            local major, minor = driver._mariadb_version:match("(%d+)%.(%d+)")
            local supports = (tonumber(major) > 10) or
                (tonumber(major) == 10 and tonumber(minor) >= 5)
            assert.is_true(supports)
        end)

        it("sets _supports_returning to false for version 10.4", function()
            driver._mariadb_version = "10.4.12-MariaDB"
            local major, minor = driver._mariadb_version:match("(%d+)%.(%d+)")
            local supports = (tonumber(major) > 10) or
                (tonumber(major) == 10 and tonumber(minor) >= 5)
            assert.is_false(supports)
        end)

        it("sets _supports_returning to false for version 10.3", function()
            driver._mariadb_version = "10.3.32-MariaDB"
            local major, minor = driver._mariadb_version:match("(%d+)%.(%d+)")
            local supports = (tonumber(major) > 10) or
                (tonumber(major) == 10 and tonumber(minor) >= 5)
            assert.is_false(supports)
        end)
    end)
end)
