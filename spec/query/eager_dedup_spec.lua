-- Tests for eager loading ID deduplication (#69)
-- Ensures IDs are deduplicated before IN clauses

describe("Eager Loading Deduplication", function()
    local Jade = require("jade")
    local Query = require("jade.query")

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
        local q = Query.new(Post)
        q._includes = { "user" }
        q:_eagerLoad(instances)

        -- Verify deduplication: the IN clause should have only one ID (1), not three (1,1,1)
        local user_query = nil
        for _, query in ipairs(queries) do
            if query.sql:match("dedup_users") then
                user_query = query
                break
            end
        end

        assert.is_truthy(user_query, "Expected a query to dedup_users table")
        -- The bindings should contain only one ID (deduplicated)
        assert.are.equal(1, #user_query.bindings, "Expected 1 deduplicated ID, got " .. #user_query.bindings)
        assert.are.equal(1, user_query.bindings[1])
        -- Verify the SQL contains IN clause with unique IDs
        assert.is_truthy(user_query.sql:match("IN"), "SQL should contain IN clause")
    end)

    it("generates query with unique IDs in IN clause", function()
        local User = Jade.Entity("dedup_users_unique", {
            id = Jade.Integer():primaryKey(),
            name = Jade.String(100),
        })

        local Post = Jade.Entity("dedup_posts_unique", {
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
                if sql:match("dedup_users_unique") then
                    return { { id = 1, name = "User 1" }, { id = 2, name = "User 2" } }
                end
                return {}
            end,
            generateSelect = function(self, query)
                return "SELECT * FROM " .. query._table, {}
            end,
        }
        User._driver = Post._driver

        -- Simulate eager loading with multiple different duplicate FKs
        local instances = {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 2 } },
            { _data = { id = 4, title = "Post 4", user_id = 2 } },
        }

        -- Call eager loading directly
        local q = Query.new(Post)
        q._includes = { "user" }
        q:_eagerLoad(instances)

        -- Verify deduplication: the IN clause should have only two IDs (1,2), not four (1,1,2,2)
        local user_query = nil
        for _, query in ipairs(queries) do
            if query.sql:match("dedup_users_unique") then
                user_query = query
                break
            end
        end

        assert.is_truthy(user_query, "Expected a query to dedup_users_unique table")
        -- The bindings should contain only two IDs (deduplicated)
        assert.are.equal(2, #user_query.bindings, "Expected 2 deduplicated IDs, got " .. #user_query.bindings)
        -- Verify unique IDs in bindings
        assert.are.equal(1, user_query.bindings[1])
        assert.are.equal(2, user_query.bindings[2])
        -- Verify the SQL contains IN clause with unique IDs
        assert.is_truthy(user_query.sql:match("IN"), "SQL should contain IN clause")
    end)

    it("deduplicates multiple duplicate foreign keys", function()
        local User = Jade.Entity("dedup_users_multi", {
            id = Jade.Integer():primaryKey(),
            name = Jade.String(100),
        })

        local Post = Jade.Entity("dedup_posts_multi", {
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
                if sql:match("dedup_users_multi") then
                    return {
                        { id = 1, name = "User 1" },
                        { id = 2, name = "User 2" },
                        { id = 3, name = "User 3" },
                    }
                end
                return {}
            end,
            generateSelect = function(self, query)
                return "SELECT * FROM " .. query._table, {}
            end,
        }
        User._driver = Post._driver

        -- Simulate eager loading with many duplicate foreign keys
        local instances = {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 1 } },
            { _data = { id = 4, title = "Post 4", user_id = 2 } },
            { _data = { id = 5, title = "Post 5", user_id = 2 } },
            { _data = { id = 6, title = "Post 6", user_id = 3 } },
            { _data = { id = 7, title = "Post 7", user_id = 3 } },
            { _data = { id = 8, title = "Post 8", user_id = 3 } },
        }

        -- Call eager loading directly
        local q = Query.new(Post)
        q._includes = { "user" }
        q:_eagerLoad(instances)

        -- Verify deduplication: the IN clause should have only three IDs (1,2,3), not eight
        local user_query = nil
        for _, query in ipairs(queries) do
            if query.sql:match("dedup_users_multi") then
                user_query = query
                break
            end
        end

        assert.is_truthy(user_query, "Expected a query to dedup_users_multi table")
        -- The bindings should contain only three IDs (deduplicated)
        assert.are.equal(3, #user_query.bindings, "Expected 3 deduplicated IDs, got " .. #user_query.bindings)
        -- Verify unique IDs in bindings
        assert.are.equal(1, user_query.bindings[1])
        assert.are.equal(2, user_query.bindings[2])
        assert.are.equal(3, user_query.bindings[3])
        -- Verify the SQL contains IN clause with unique IDs
        assert.is_truthy(user_query.sql:match("IN"), "SQL should contain IN clause")
    end)
end)
