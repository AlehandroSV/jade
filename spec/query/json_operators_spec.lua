--- Tests for JSON operator integration in Condition and Expression.

describe("JSON Operators", function()
    local Json = require("jade.query.json")

    ----------------------------------------------------------------
    -- Path parsing
    ----------------------------------------------------------------

    describe("Json.parsePath", function()
        it("parses a simple key path", function()
            local result = Json.parsePath("metadata")
            assert.are.equal(1, #result)
            assert.are.equal("metadata", result[1])
        end)

        it("parses a nested path", function()
            local result = Json.parsePath("config.theme")
            assert.are.equal(2, #result)
            assert.are.equal("config", result[1])
            assert.are.equal("theme", result[2])
        end)

        it("parses paths with array indices as numbers", function()
            local result = Json.parsePath("tags[0].name")
            assert.are.equal(3, #result)
            assert.are.equal("tags", result[1])
            assert.is_true(type(result[2]) == "number")
            assert.are.equal(0, result[2])
            assert.are.equal("name", result[3])
        end)

        it("handles empty path", function()
            assert.are.equal(0, #Json.parsePath(""))
        end)
    end)

    ----------------------------------------------------------------
    -- Driver SQL generation (no DB needed)
    ----------------------------------------------------------------

    describe("Json.pgSelectSql", function()
        it("generates PG arrow operators for key lookup", function()
            local sql, bindings = Json.pgSelectSql("metadata", {"email"}, false)
            assert.is_true(#sql > 0)
            assert.is_true(string.find(sql, "->") ~= nil)
            assert.are.equal(1, #bindings)
            assert.are.equal("email", bindings[1])
        end)

        it("generates ::text cast for text extraction", function()
            local sql, bindings = Json.pgSelectSql("metadata", {"email"}, true)
            assert.is_true(string.find(sql, "::text") ~= nil)
        end)

        it("handles nested paths", function()
            local sql, bindings = Json.pgSelectSql("data", {"config", "theme"}, false)
            assert.is_true(#sql > 0)
            assert.are.equal(2, #bindings)
        end)

        it("handles array indices", function()
            local sql, bindings = Json.pgSelectSql("arr", {"tags", 0}, false)
            assert.is_true(string.find(sql, "->") ~= nil)
            assert.are.equal(1, #bindings)
            assert.are.equal("tags", bindings[1])
        end)
    end)

    describe("Json.mySelectSql", function()
        it("generates JSON_EXTRACT for MySQL", function()
            local sql, bindings = Json.mySelectSql("metadata", {"email"}, false)
            assert.is_true(string.find(sql, "JSON_EXTRACT") ~= nil)
        end)

        it("generates JSON_UNQUOTE(JSON_EXTRACT()) for text", function()
            local sql, bindings = Json.mySelectSql("metadata", {"email"}, true)
            assert.is_true(string.find(sql, "JSON_UNQUOTE") ~= nil)
            assert.is_true(string.find(sql, "JSON_EXTRACT") ~= nil)
        end)
    end)

    describe("Json.sqliteSelectSql", function()
        it("generates json_extract for SQLite", function()
            local sql, bindings = Json.sqliteSelectSql("metadata", {"email"}, false)
            assert.is_true(string.find(sql, "json_extract") ~= nil)
        end)
    end)

    describe("Json.pgJsonContainsSql", function()
        it("generates @> condition for PG", function()
            local sql, bindings = Json.pgJsonContainsSql("metadata", {"role"}, '{"role": "admin"}')
            assert.is_true(#sql > 0)
            assert.is_true(string.find(sql, "@>") ~= nil)
            assert.are.equal(1, #bindings)
        end)
    end)

    describe("Json.myJsonContainsSql", function()
        it("generates JSON_CONTAINS for MySQL", function()
            local sql, bindings = Json.myJsonContainsSql("metadata", {"role"}, '["admin"]')
            assert.is_true(string.find(sql, "JSON_CONTAINS") ~= nil)
        end)
    end)

    describe("Json.pgJsonExistsSql", function()
        it("generates ? exists condition for PG", function()
            local sql, bindings = Json.pgJsonExistsSql("metadata", {"role"})
            assert.is_true(#sql > 0)
        end)
    end)

    describe("Json.myJsonExistsSql", function()
        it("generates JSON_CONTAINS_PATH for MySQL", function()
            local sql, bindings = Json.myJsonExistsSql("metadata", {"role"})
            assert.is_true(string.find(sql, "JSON_CONTAINS_PATH") ~= nil)
        end)
    end)

    ----------------------------------------------------------------
    -- Single-key shortcut (no dots in path)
    ----------------------------------------------------------------

    describe("Sql quoting via Quoting.quoteIdentifier", function()
        it("pgSelectSql uses double-quoted identifier", function()
            local sql = Json.pgSelectSql("metadata", {"email"}, false)
            assert.is_true(sql:find('"metadata"') ~= nil)
        end)

        it("mySelectSql uses quoted identifier", function()
            local sql = Json.mySelectSql("metadata", {"email"}, false)
            assert.is_true(sql:find('JSON_EXTRACT') ~= nil)
        end)

        it("sqliteSelectSql uses quoted identifier", function()
            local sql = Json.sqliteSelectSql("metadata", {"email"}, false)
            assert.is_true(sql:find('"metadata"') ~= nil)
        end)

        it("pgJsonContainsSql uses quoted identifier", function()
            local sql = Json.pgJsonContainsSql("metadata", {"role"}, '{"role":"admin"}')
            assert.is_true(sql:find('"metadata"') ~= nil)
            assert.is_true(sql:find("@>") ~= nil)
        end)

        it("myJsonContainsSql uses quoted identifier", function()
            local sql = Json.myJsonContainsSql("metadata", {"role"}, '["admin"]')
            assert.is_true(sql:find('JSON_CONTAINS') ~= nil)
        end)

        it("sqliteJsonContainsSql uses quoted identifier", function()
            local sql = Json.sqliteJsonContainsSql("metadata", {"role"}, 'test')
            assert.is_true(sql:find('json_extract') ~= nil)
            assert.is_true(sql:find('"metadata"') ~= nil)
        end)

        it("pgJsonExistsSql uses quoted identifier", function()
            local sql = Json.pgJsonExistsSql("metadata", {"role"})
            assert.is_true(sql:find('"metadata" ? ?') ~= nil)
        end)

        it("myJsonExistsSql uses quoted identifier", function()
            local sql = Json.myJsonExistsSql("metadata", {"role"})
            assert.is_true(sql:find('JSON_CONTAINS_PATH') ~= nil)
        end)

        it("sqliteJsonExistsSql uses quoted identifier", function()
            local sql = Json.sqliteJsonExistsSql("metadata", {"role"})
            assert.is_true(sql:find('json_length(json_extract') ~= nil)
            assert.is_true(sql:find('"metadata"') ~= nil)
        end)
    end)

    ----------------------------------------------------------------
    -- JSON special character escaping (injection prevention)
    ----------------------------------------------------------------

    describe("Expression jsonContains escaping", function()
        local ExprBase = require("jade.query.expression")
        local expr = ExprBase.new("metadata", "users")

        before_each(function()
            package.loaded["jade.query.json"] = nil
            package.loaded["jade.util.quoting"] = nil
            package.loaded["jade.query.condition"] = nil
            package.loaded["jade.query.expression-json"] = nil
        end)

        after_each(function()
            package.loaded["jade.query.json"] = nil
            package.loaded["jade.util.quoting"] = nil
            package.loaded["jade.query.condition"] = nil
            package.loaded["jade.query.expression-json"] = nil
        end)

        it("escapes double quotes in key value", function()
            local Cond = require("jade.query.condition")
            Cond.new = function(col, op, val, tbl)
                assert.are.equal(col, "metadata")
                assert.are.equal(op, "@>")
                -- Should contain escaped quote
                assert.is_true(val:find('\\"') ~= nil or val:find(['[\\][\\]']) ~= nil)
                return {}
            end
            local j = require("jade.query.expression-json")(ExprBase)
            expr:jsonContains('key"name', 'value')
        end)

        it("escapes backslashes in key value", function()
            local Cond = require("jade.query.condition")
            Cond.new = function(col, op, val, tbl)
                assert.are.equal(col, "metadata")
                assert.are.equal(op, "@>")
                assert.is_true(val:find('\\\\\\') ~= nil)
                return {}
            end
            local j = require("jade.query.expression-json")(ExprBase)
            expr:jsonContains('key\\name', 'value')
        end)
    end)
end)
