-- Tests for safe deleteAll() / updateAll() (#119)
-- These methods must require an explicit .where() filter to prevent accidental full-table operations.

local Jade = require("jade")
if not Jade._instance then
    Jade.configure({ driver = "sqlite", database = ":memory:" })
end

describe("Safe bulk operations", function()
    local Post
    before_each(function()
        Post = Jade.Entity("posts_bu" .. math.random(1000), {
            id = Jade.Integer():primaryKey(),
            title = Jade.String(200),
        })
        Post._driver = { 
            execute = function(sql, bindings) return {{}} end,
            generateBulkDelete = function(tname, where) return "DELETE FROM dummy", {} end,
            generateBulkUpdate = function(tname, data, where) return "UPDATE dummy SET 1=1", {} end,
        }
        Post._columns = Post._columns or {}
        Post._relations = Post._relations or {}
    end)

    describe("Bug #119: deleteAll() requer .where() explícito", function()
        it("raises error when called without .where()", function()
            local q = Post:scope()
            assert.has_error(function()
                q:deleteAll()
            end)
        end)

        it("succeeds when .where() is explicitly applied", function()
            local q = Post:scope()
            q:where(Jade.raw("id = ?", 1))
            -- Não deve levantar error
            local ok, err = pcall(function()
                q:deleteAll()
            end)
            assert.is_true(ok, "deleteAll() com .where() deve passar")
        end)

        it("succeeds with compound where conditions", function()
            local q = Post:scope()
            q:where(Jade.raw("active = ?", true)):where(Jade.raw("score > ?", 50))
            assert.has_no_error(function()
                q:deleteAll()
            end)
        end)
    end)

    describe("Bug #119: updateAll(data) requer .where() explícito", function()
        it("raises error when called without .where()", function()
            local q = Post:scope()
            assert.has_error(function()
                q:updateAll({ title = "new" })
            end)
        end)

        it("succeeds when .where() is explicitly applied", function()
            local q = Post:scope()
            q:where(Jade.raw("id IN (?, ?)", 1, 2))
            assert.has_no_error(function()
                q:updateAll({ title = "updated" })
            end)
        end)
    end)
end)
