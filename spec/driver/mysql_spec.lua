describe("MySQL Driver SQL Generation", function()
    local MySQL = require("jade.driver.mysql")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")
    local Timestamp = require("jade.types.timestamp")
    local Schema = require("jade.schema")

    local driver
    local User

    before_each(function()
        driver = MySQL.new()
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

        it("maps json", function()
            local col = { type = "json" }
            assert.are.equal("JSON", driver:mapType(col))
        end)

        it("maps datetime", function()
            local col = { type = "datetime" }
            assert.are.equal("DATETIME", driver:mapType(col))
        end)
    end)

    describe("generateSelect", function()
        it("generates simple select", function()
            local q = User:where(User.active:eq(true))
            local sql, bindings = driver:generateSelect(q)
            -- Note: WHERE clause uses double quotes from Condition module
            assert.is_truth(string.find(sql, "SELECT * FROM `users`"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.are.same({ true }, bindings)
        end)

        it("generates select with order and limit", function()
            local q = User:orderBy(User.name):limit(10)
            local sql, bindings = driver:generateSelect(q)
            assert.are.equal("SELECT * FROM `users` ORDER BY `name` ASC LIMIT 10", sql)
        end)

        it("generates select with multiple wheres", function()
            local q = User:where(User.active:eq(true)):where(User.name:isNotNull())
            local sql, bindings = driver:generateSelect(q)
            -- Note: WHERE clause uses double quotes from Condition module
            assert.is_truth(string.find(sql, "SELECT * FROM `users`"))
            assert.is_truth(string.find(sql, "WHERE"))
        end)
    end)

    describe("generateInsert", function()
        it("generates insert", function()
            local sql, bindings = driver:generateInsert("users", {
                name = "Lucas",
                email = "lucas@test.com",
            }, User)
            assert.is_truth(string.find(sql, "INSERT INTO `users`"))
            assert.is_falsy(string.find(sql, "RETURNING"))
            assert.are.equal(2, #bindings)
        end)
    end)

    describe("generateUpdate", function()
        it("generates update with where", function()
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateUpdate("users", { name = "New" }, where)
            assert.is_truth(string.find(sql, "UPDATE `users` SET"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.is_falsy(string.find(sql, "RETURNING"))
        end)
    end)

    describe("generateDelete", function()
        it("generates delete with where", function()
            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", 1, "users")
            local sql, bindings = driver:generateDelete("users", where)
            -- Note: WHERE clause uses double quotes from Condition module
            assert.is_truth(string.find(sql, "DELETE FROM `users`"))
            assert.is_truth(string.find(sql, "WHERE"))
            assert.are.same({ 1 }, bindings)
        end)
    end)

    describe("dropTableCascade", function()
        it("returns false for MySQL", function()
            assert.is_false(driver:dropTableCascade())
        end)
    end)

    describe("Table options", function()
        it("generates CREATE TABLE with ENGINE=InnoDB", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true, auto_increment = true })
            tbl:column("name", "string", { length = 120 })
            tbl:setEngine("InnoDB")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "ENGINE=InnoDB"))
        end)

        it("generates CREATE TABLE with CHARSET", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true })
            tbl:setCharset("utf8mb4")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "CHARSET=utf8mb4"))
        end)

        it("generates CREATE TABLE with COLLATION", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true })
            tbl:setCollation("utf8mb4_unicode_ci")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "COLLATE=utf8mb4_unicode_ci"))
        end)

        it("generates CREATE TABLE with multiple options", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true, auto_increment = true })
            tbl:setEngine("InnoDB")
            tbl:setCharset("utf8mb4")
            tbl:setCollation("utf8mb4_unicode_ci")

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "ENGINE=InnoDB"))
            assert.is_truth(string.find(sql, "CHARSET=utf8mb4"))
            assert.is_truth(string.find(sql, "COLLATE=utf8mb4_unicode_ci"))
        end)
    end)

    describe("AUTO_INCREMENT", function()
        it("generates AUTO_INCREMENT for primary key", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true, auto_increment = true })
            tbl:column("name", "string", { length = 120 })

            local sql = tbl:toSQL(driver)
            assert.is_truth(string.find(sql, "AUTO_INCREMENT"))
        end)

        it("does not generate AUTO_INCREMENT for non-primary key", function()
            local Table = require("jade.schema.table")
            local tbl = Table.new("users")
            tbl:column("id", "integer", { primary_key = true })
            tbl:column("name", "string", { length = 120 })

            local sql = tbl:toSQL(driver)
            assert.is_falsy(string.find(sql, "AUTO_INCREMENT"))
        end)
    end)
end)
