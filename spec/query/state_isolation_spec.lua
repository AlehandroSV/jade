-- Tests for Query state mutation bugs (#112, #113)
local Jade = require("jade")
-- Configure globally first so _resolveTimeout doesn't error
if not Jade._instance then
    Jade.configure({ driver = "sqlite", database = ":memory:" })
end

describe("Query state isolation", function()
    local function makeEntity(table_name)
        local Post = Jade.Entity(table_name .. math.random(1000), {
            id = Jade.Integer():primaryKey(),
            title = Jade.String(200),
        })
        require("jade.entity.soft_delete").setup(Post)
        Post._driver = {
            execute = function() return {{}} end,
            generateSelect = function(q) return "SELECT * FROM dummy", {} end,
        }
        Post._columns = Post._columns or {}
        Post._relations = Post._relations or {}
        return Post
    end

    describe("Bug #112: toSQL() não deve mutar self._where persistentemente", function()
        it("soft-delete filter applied without growing _where permanently", function()
            local Post = makeEntity("posts_td_112a")
            local q = Post:scope()

            assert.are.equal(0, #q._where, "Inicialmente sem conditions no _where")

            -- toSQL() aplica soft-delete temporariamente para gerar SQL
            q:get()  -- primeira chamada
            -- Após get(), _where volta ao estado original (0) porque mutation foi isolada
            assert.are.equal(0, #q._where, "_where não cresce em chamadas repetidas")

            q:get()  -- segunda
            assert.are.equal(0, #q._where, "_where permanece estável")

            q:get()  -- terceira
            assert.are.equal(0, #q._where, "_where permanece estável")
        end)

        it("does not accumulate filters on repeated count()", function()
            local Post = makeEntity("posts_td_112b")
            local q = Post:scope()
            assert.are.equal(0, #q._where)

            q:count()
            local n1 = #q._where

            q:count()
            assert.are.equal(n1, #q._where, "_where não cresce em contagens repetidas")
        end)
    end)

    describe("Bug #113: aggregate methods fazem deep copy de _where", function()
        it("first() does not modify the original query's _where", function()
            local Post = makeEntity("posts_td_113a")
            local q = Post:scope()
            q:where(Jade.raw("title IS NOT NULL"))
            local orig_len = #q._where

            q:first()

            assert.are.equal(orig_len, #q._where, "first() não altera _where original")
        end)

        it("count() does not modify the original query's _where", function()
            local Post = makeEntity("posts_td_113b")
            local q = Post:scope()
            q:where(Jade.raw("active = ?", true))
            local orig_len = #q._where

            q:count()
            assert.are.equal(orig_len, #q._where, "count() não altera _where original")
        end)

        it("pluck() does not modify the original query's _where", function()
            local Post = makeEntity("posts_td_113c")
            local q = Post:scope()
            q:where(Jade.raw("1=1"))
            local orig_len = #q._where

            q:pluck("title")
            assert.are.equal(orig_len, #q._where, "pluck() não altera _where original")
        end)

        it("multiple aggregates in sequence do not compound mutations", function()
            local Post = makeEntity("posts_td_113d")
            local q = Post:scope()
            q:where(Jade.raw("score > 0"))
            local orig_len = #q._where

            q:first()
            assert.are.equal(orig_len, #q._where, "first() não alterou")

            q:count()
            assert.are.equal(orig_len, #q._where, "count() não alterou")

            q:min("score")
            assert.are.equal(orig_len, #q._where, "min() não alterou")
        end)
    end)
end)
