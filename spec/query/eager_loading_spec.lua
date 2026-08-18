describe("Eager Loading Validation", function()
    local Entity = require("jade.entity")
    local Query = require("jade.query")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")

    -- Mock driver for testing SQL generation
    local mock_driver = {
        generateSelect = function(self, query)
            return "SELECT * FROM mock_table", {}
        end,
    }

    local User
    local Post
    local Comment

    before_each(function()
        -- Create fresh entities to avoid cross-test pollution
        User = Entity.new("users_e88", {
            id = Integer():primaryKey(),
            name = String(120),
        })

        Post = Entity.new("posts_e88", {
            id = Integer():primaryKey(),
            title = String(255),
            user_id = Integer(),
        })

        Comment = Entity.new("comments_e88", {
            id = Integer():primaryKey(),
            body = String(),
            post_id = Integer(),
        })

        User:hasMany(Post)
        Post:belongsTo(User)
        Post:hasMany(Comment)
        Comment:belongsTo(Post)

        User:configure(mock_driver)
        Post:configure(mock_driver)
        Comment:configure(mock_driver)
    end)

    describe("_eagerLoad invalid relation names", function()
        it("throws error when include references a non-existent relation", function()
            local q = Query.new(User)
            q._includes = {"nonexistent_relation"}

            assert.has_error(function()
                q:_eagerLoad({})
            end)
        end)

        it("includes the relation name in the error message", function()
            local q = Query.new(User)
            q._includes = {"wrong_relation_name_xyz"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("wrong_relation_name_xyz"), "Error should mention 'wrong_relation_name_xyz': " .. msg)
        end)

        it("includes the entity table name in the error message", function()
            local q = Query.new(User)
            q._includes = {"missing_relation_abc"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("users_e88"), "Error should mention 'users_e88': " .. msg)
        end)

        it("lists available relations in the error message", function()
            local q = Query.new(User)
            q._includes = {"typo_here"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("posts_e88"), "Should list 'posts_e88' as an available relation: " .. msg)
        end)

        it("validates multiple includes and stops at first invalid", function()
            local q = Query.new(User)
            q._includes = {"posts_e88", "does_not_exist_xyz", "also_missing_xyz"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("does_not_exist_xyz"), "Should mention 'does_not_exist_xyz': " .. msg)
        end)

        it("does NOT throw error when all included relations exist", function()
            local q = Query.new(User)
            q._includes = {"posts_e88"}

            -- Should not error even with empty instances
            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_true(ok, "No error should be raised for valid relations")
        end)

        it("returns early on empty instances without validating relations", function()
            local q = Query.new(User)
            q._includes = {"nonexistent_xyz"}

            -- According to PADRAO.md proposal, this should still validate
            -- because the typo is a developer error regardless of data
            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
        end)

        it("shows correct relations for Post entity", function()
            local q = Query.new(Post)
            q._includes = {"invalid_rel_xyz"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("users_e88"), "Should list 'users_e88' belongsTo: " .. msg)
            assert.is_truthy(msg:find("comments_e88"), "Should list 'comments_e88' hasMany: " .. msg)
        end)

        it("reports duplicate wrong includes consistently", function()
            local q = Query.new(User)
            q._includes = {"bad_name_xyz", "bad_name_xyz"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("bad_name_xyz"), "Should mention 'bad_name_xyz': " .. msg)
        end)

        it("handles empty string relation name", function()
            local q = Query.new(User)
            q._includes = {""}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("relation"), "Should mention 'relation': " .. msg)
        end)

        it("rejects relation name that partially matches but is different", function()
            local q = Query.new(User)
            q._includes = {"PostWrong"}  -- Wrong case/pattern

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("PostWrong"), "Error should mention 'PostWrong': " .. msg)
        end)

        it("rejects underscored version when camelCase used", function()
            local q = Query.new(User)
            q._includes = {"has_many_posts_xyz"}

            local ok, err = pcall(function()
                q:_eagerLoad({})
            end)

            assert.is_false(ok)
            local msg = tostring(err)
            assert.is_truthy(msg:find("has_many_posts_xyz"), "Error should mention 'has_many_posts_xyz': " .. msg)
        end)
    end)
end)
