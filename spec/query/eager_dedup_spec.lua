-- Tests for eager loading ID deduplication (#69)
-- Ensures IDs are deduplicated before IN clauses

describe("Eager Loading Deduplication", function()
    local Jade = require("jade")
    local Query = require("jade.query")

    -- Helper: capture WHERE conditions set during _eagerLoad by overriding generateSelect
    local function capture_conditions(entity_table_prefix, rel_name_suffix, instances, expected_rel_key)
        local User = Jade.Entity(entity_table_prefix .. "_users", {
            id = Jade.Integer():primaryKey(),
            name = Jade.String(100),
        })

        local Post = Jade.Entity(entity_table_prefix .. "_posts", {
            id = Jade.Integer():primaryKey(),
            title = Jade.String(255),
            user_id = Jade.Integer(),
        })
        Post:belongsTo(User, { foreign_key = "user_id" })

        local captured_conds = {}

        Post._driver = {
            execute = function(self, sql, bindings)
                return {} -- Return empty results; we only care about WHERE conditions
            end,
            generateSelect = function(self, query)
                -- Capture any WHERE conditions set on the query
                if query._where and #query._where > 0 then
                    captured_conds[#captured_conds + 1] = {
                        where = query._where,
                        table = query._table,
                    }
                end
                return "SELECT * FROM " .. (query._table or "unknown"), {}
            end,
        }
        User._driver = Post._driver

        local q = Query.new(Post)
        q._includes = { expected_rel_key }
        q:_eagerLoad(instances)

        return captured_conds
    end

    it("deduplicates belongsTo IDs", function()
        -- For entity names "dedup_users" → singular = "dedup_user" (different!)
        -- So relations registered: "dedup_users" AND "dedup_user"
        local conds = capture_conditions("dedup", "dedup_user", {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 1 } },
        }, "dedup_user")

        assert.is_truthy(#conds > 0, "Expected at least one WHERE condition")
        local cond = conds[1].where[1]
        assert.are.equal("IN", cond.op, "Expected IN operator")
        -- Only 1 unique ID (not 3 duplicates of 1)
        assert.are.equal(1, #cond.value, "Expected 1 deduplicated ID")
    end)

    it("generates query with unique IDs in IN clause", function()
        -- Entity names become "dedup_users_unique_users" → singular = "dedup_users_unique_user"
        local conds = capture_conditions("dedup_users_unique", "dedup_users_unique_user", {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 2 } },
            { _data = { id = 4, title = "Post 4", user_id = 2 } },
        }, "dedup_users_unique_user")

        assert.is_truthy(#conds > 0, "Expected at least one WHERE condition")
        local cond = conds[1].where[1]
        assert.are.equal("IN", cond.op)
        -- 2 unique IDs (1, 2), not 4
        assert.are.equal(2, #cond.value, "Expected 2 deduplicated IDs")
        assert.are.equal(1, cond.value[1])
        assert.are.equal(2, cond.value[2])
    end)

    it("deduplicates multiple duplicate foreign keys", function()
        -- Entity names become "dedup_users_multi_users" → singular = "dedup_users_multi_user"
        local conds = capture_conditions("dedup_users_multi", "dedup_users_multi_user", {
            { _data = { id = 1, title = "Post 1", user_id = 1 } },
            { _data = { id = 2, title = "Post 2", user_id = 1 } },
            { _data = { id = 3, title = "Post 3", user_id = 1 } },
            { _data = { id = 4, title = "Post 4", user_id = 2 } },
            { _data = { id = 5, title = "Post 5", user_id = 2 } },
            { _data = { id = 6, title = "Post 6", user_id = 3 } },
            { _data = { id = 7, title = "Post 7", user_id = 3 } },
            { _data = { id = 8, title = "Post 8", user_id = 3 } },
        }, "dedup_users_multi_user")

        assert.is_truthy(#conds > 0, "Expected at least one WHERE condition")
        local cond = conds[1].where[1]
        assert.are.equal("IN", cond.op)
        -- 3 unique IDs (1, 2, 3), not 8
        assert.are.equal(3, #cond.value, "Expected 3 deduplicated IDs")
        assert.are.equal(1, cond.value[1])
        assert.are.equal(2, cond.value[2])
        assert.are.equal(3, cond.value[3])
    end)
end)
