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
end)
