describe("Query Builder", function()
    local Entity = require("jade.entity")
    local Query = require("jade.query")
    local Quoting = require("jade.util.quoting")

    -- Mock driver for testing SQL generation
    local mock_driver = {
        generateSelect = function(self, query)
            local sql = {}
            local bindings = {}

            if #query._select > 0 then
                sql[#sql + 1] = "SELECT " .. table.concat(query._select, ", ")
            else
                sql[#sql + 1] = "SELECT *"
            end

            sql[#sql + 1] = "FROM " .. Quoting.quoteIdentifier(query._table)

            if #query._where > 0 then
                local where_parts = {}
                for _, cond in ipairs(query._where) do
                    local sql_part, bind = cond:compile()
                    where_parts[#where_parts + 1] = sql_part
                    for _, b in ipairs(bind) do
                        bindings[#bindings + 1] = b
                    end
                end
                sql[#sql + 1] = "WHERE " .. table.concat(where_parts, " AND ")
            end

            if #query._orderBy > 0 then
                local order_parts = {}
                for _, o in ipairs(query._orderBy) do
                    order_parts[#order_parts + 1] = Quoting.quoteIdentifier(o.column) .. " " .. o.dir
                end
                sql[#sql + 1] = "ORDER BY " .. table.concat(order_parts, ", ")
            end

            if query._limit then
                sql[#sql + 1] = "LIMIT " .. tostring(query._limit)
            end
            if query._offset then
                sql[#sql + 1] = "OFFSET " .. tostring(query._offset)
            end

            return table.concat(sql, " "), bindings
        end,
    }

    local User

    before_each(function()
        User = Entity.new("users", {
            id = require("jade.types.integer")():primaryKey(),
            name = require("jade.types.string")(120),
            email = require("jade.types.string")():unique(),
            age = require("jade.types.integer")(),
            active = require("jade.types.boolean")():default(true),
        })
        User:configure(mock_driver)
    end)

    it("generates simple SELECT", function()
        local q = Query.new(User)
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users"', sql)
        assert.are.same({}, bindings)
    end)

    it("generates SELECT with WHERE", function()
        local q = Query.new(User):where(User.age:gt(18))
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users" WHERE "users"."age" > ?', sql)
        assert.are.same({ 18 }, bindings)
    end)

    it("generates SELECT with ORDER BY", function()
        local q = Query.new(User):orderBy(User.name)
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users" ORDER BY "name" ASC', sql)
    end)

    it("generates SELECT with ORDER BY DESC", function()
        local q = Query.new(User):orderBy(User.name, "DESC")
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users" ORDER BY "name" DESC', sql)
    end)

    it("generates SELECT with LIMIT", function()
        local q = Query.new(User):limit(10)
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users" LIMIT 10', sql)
    end)

    it("generates SELECT with OFFSET", function()
        local q = Query.new(User):limit(10):offset(20)
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT * FROM "users" LIMIT 10 OFFSET 20', sql)
    end)

    it("generates SELECT with specific columns", function()
        local q = Query.new(User):select("id", "name")
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT id, name FROM "users"', sql)
    end)

    it("chains multiple clauses", function()
        local q = Query.new(User)
            :where(User.active:eq(true))
            :where(User.age:gt(18))
            :orderBy(User.name)
            :limit(20)
        local sql, bindings = q:toSQL()
        assert.are.equal(
            'SELECT * FROM "users" WHERE "users"."active" = ? AND "users"."age" > ? ORDER BY "name" ASC LIMIT 20',
            sql
        )
        assert.are.same({ true, 18 }, bindings)
    end)

    it("generates COUNT query", function()
        local q = Query.new(User):where(User.active:eq(true))
        q._select = { "COUNT(*) as count" }
        local sql, bindings = q:toSQL()
        assert.are.equal('SELECT COUNT(*) as count FROM "users" WHERE "users"."active" = ?', sql)
    end)
end)
