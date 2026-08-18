-- Tests for Query:exists() performance optimization (#89)
-- exists() should use SELECT 1 LIMIT 1 instead of COUNT(*)

describe("Query:exists() optimization", function()
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")

    local captured_sql = nil
    local mock_driver

    before_each(function()
        captured_sql = nil
        mock_driver = {
            execute = function(self, sql, bindings)
                captured_sql = sql
                -- Simulate: return 1 row if SQL has no WHERE or has matching rows
                if sql:match("LIMIT 1") then
                    return { { id = 1 } }
                end
                return {}
            end,
            generateSelect = function(self, query)
                local sql_parts = {}
                if #query._select > 0 then
                    sql_parts[#sql_parts + 1] = "SELECT " .. table.concat(query._select, ", ")
                else
                    sql_parts[#sql_parts + 1] = "SELECT *"
                end
                sql_parts[#sql_parts + 1] = "FROM " .. query._table
                if query._limit then
                    sql_parts[#sql_parts + 1] = "LIMIT " .. tostring(query._limit)
                end
                return table.concat(sql_parts, " "), {}
            end,
        }
    end)

    it("uses SELECT 1 instead of SELECT * or COUNT(*)", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(100),
        })
        User._driver = mock_driver

        User:exists()

        assert.is_truthy(captured_sql)
        assert.is_truthy(string.find(captured_sql, "SELECT 1"))
        assert.is_falsy(string.find(captured_sql, "COUNT"))
        assert.is_falsy(string.find(captured_sql, "SELECT %*"))
    end)

    it("uses LIMIT 1", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(100),
        })
        User._driver = mock_driver

        User:exists()

        assert.is_truthy(captured_sql)
        assert.is_truthy(string.find(captured_sql, "LIMIT 1"))
    end)

    it("returns true when records exist", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(100),
        })
        User._driver = mock_driver

        local result = User:exists()
        assert.is_true(result)
    end)

    it("returns false when no records exist", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(100),
        })
        local empty_driver = {
            execute = function(self, sql, bindings)
                captured_sql = sql
                return {}
            end,
            generateSelect = function(self, query)
                local sql_parts = {}
                if #query._select > 0 then
                    sql_parts[#sql_parts + 1] = "SELECT " .. table.concat(query._select, ", ")
                else
                    sql_parts[#sql_parts + 1] = "SELECT *"
                end
                sql_parts[#sql_parts + 1] = "FROM " .. query._table
                if query._limit then
                    sql_parts[#sql_parts + 1] = "LIMIT " .. tostring(query._limit)
                end
                return table.concat(sql_parts, " "), {}
            end,
        }
        User._driver = empty_driver

        local result = User:exists()
        assert.is_false(result)
    end)

    it("passes where options to query", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(100),
            status = String(20),
        })
        User._driver = mock_driver

        User:exists({ where = { status = "active" } })

        assert.is_truthy(captured_sql)
        assert.is_truthy(string.find(captured_sql, "status"))
    end)
end)
