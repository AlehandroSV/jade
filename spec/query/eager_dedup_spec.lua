-- Tests for eager loading ID deduplication (#69)
-- Ensures IDs are deduplicated before IN clauses

describe("Eager Loading Deduplication", function()
    local Jade = require("jade")

    it("deduplicates belongsTo IDs", function()
        local User = Jade.Entity("dedup_users", {
            id = Jade.Integer():primaryKey(),
            name = Jade.String(100),
        })

        local Post = Jade.Entity("dedup_posts", {
            id = Jade.Integer():primaryKey(),
            title = Jade.String(255),
            user_id = Jade.Integer(),
        })
        Post:belongsTo(User, { foreign_key = "user_id" })

        -- Track executed queries
        local queries = {}
        Post._driver = {
            execute = function(self, sql, bindings)
                queries[#queries + 1] = { sql = sql, bindings = bindings }
                -- Return mock data for user query
                if sql:match("dedup_users") then
                    return { { id = 1, name = "User 1" } }
                end
                return {}
            end,
            generateSelect = function(self, query)
                return "SELECT * FROM " .. query._table, {}
            end,
        }
        User._driver = Post._driver

        -- Simulate eager loading with duplicate FKs
        local instances = {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 1 } },
        }

        -- Call eager loading directly
        local Query = require("jade.query")
        local q = Query.new(Post)
        q._includes = { "user" }
        q:_eagerLoad(instances)

        -- Verify deduplication: the IN clause should have only one ID (1), not three (1,1,1)
        local user_query = nil
        for _, q in ipairs(queries) do
            if q.sql:match("dedup_users") then
                user_query = q
                break
            end
        end

        assert.is_truthy(user_query, "Expected a query to dedup_users table")
        -- The bindings should contain only one ID (deduplicated)
        assert.are.equal(1, #user_query.bindings, "Expected 1 deduplicated ID, got " .. #user_query.bindings)
        assert.are.equal(1, user_query.bindings[1])
    end)
end)
