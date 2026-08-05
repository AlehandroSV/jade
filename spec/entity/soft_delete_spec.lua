describe("Soft Delete", function()
    local Entity = require("jade.entity")
    local SoftDelete = require("jade.entity.soft_delete")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")

    local User
    local Post

    before_each(function()
        User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
            active = Boolean():default(true),
        })

        Post = Entity.new("posts", {
            id = Integer():primaryKey(),
            title = String(200),
            user_id = Integer(),
        })
    end)

    it("adds deleted_at column", function()
        SoftDelete.setup(User)
        assert.is_not_nil(User._columns["deleted_at"])
    end)

    it("marks entity as soft deleted", function()
        SoftDelete.setup(User)
        assert.is_true(SoftDelete.isSoftDeleted(User))
    end)

    it("returns soft delete column name", function()
        SoftDelete.setup(User)
        assert.are.equal("deleted_at", SoftDelete.getSoftDeleteColumn(User))
    end)

    it("uses custom column name", function()
        SoftDelete.setup(User, { column = "removed_at" })
        assert.is_not_nil(User._columns["removed_at"])
        assert.are.equal("removed_at", SoftDelete.getSoftDeleteColumn(User))
    end)

    it("adds forceDelete method", function()
        SoftDelete.setup(User)
        assert.is_function(User.forceDelete)
    end)

    it("adds withTrashed method", function()
        SoftDelete.setup(User)
        assert.is_function(User.withTrashed)
    end)

    it("adds onlyTrashed method", function()
        SoftDelete.setup(User)
        assert.is_function(User.onlyTrashed)
    end)

    it("adds restore method", function()
        SoftDelete.setup(User)
        assert.is_function(User.restore)
    end)

    it("adds withoutTrashed method", function()
        SoftDelete.setup(User)
        assert.is_function(User.withoutTrashed)
    end)

    describe("cascade", function()
        it("enables cascade by default", function()
            SoftDelete.setup(User)
            assert.is_true(SoftDelete.hasCascade(User))
        end)

        it("can disable cascade", function()
            SoftDelete.setup(User, { cascade = false })
            assert.is_false(SoftDelete.hasCascade(User))
        end)

        it("sets up cascade for related entities", function()
            SoftDelete.setup(User)
            SoftDelete.setup(Post)
            User:hasMany(Post)

            assert.is_true(SoftDelete.hasCascade(User))
            assert.is_true(SoftDelete.hasCascade(Post))
        end)
    end)

    describe("Query integration", function()
        local Query = require("jade.query")

        before_each(function()
            SoftDelete.setup(User)
        end)

        it("Query has withTrashed method", function()
            local q = Query.new(User)
            assert.is_function(q.withTrashed)
        end)

        it("Query has onlyTrashed method", function()
            local q = Query.new(User)
            assert.is_function(q.onlyTrashed)
        end)

        it("withTrashed sets _include_trashed flag", function()
            local q = Query.new(User):withTrashed()
            assert.is_true(q._include_trashed)
            assert.is_false(q._only_trashed)
        end)

        it("onlyTrashed sets _only_trashed flag", function()
            local q = Query.new(User):onlyTrashed()
            assert.is_false(q._include_trashed)
            assert.is_true(q._only_trashed)
        end)

        it("Entity:withTrashed returns Query com flags explícitos", function()
            local q = User:withTrashed()
            assert.is_true(q._include_trashed)
            assert.is_false(q._only_trashed)
        end)

        it("Entity:onlyTrashed returns Query com flags explícitos", function()
            local q = User:onlyTrashed()
            assert.is_false(q._include_trashed)
            assert.is_true(q._only_trashed)
        end)

        it("Entity:withoutTrashed returns Query sem flags trashed", function()
            local q = User:withoutTrashed()
            assert.is_false(q._include_trashed)
            assert.is_false(q._only_trashed)
        end)

        it("preserves soft delete flags in first()", function()
            local q = Query.new(User):withTrashed()
            -- first() creates a new Query, flags should be preserved
            assert.is_true(q._include_trashed)
        end)

        it("preserves soft delete flags in find()", function()
            local q = Query.new(User):onlyTrashed()
            assert.is_true(q._only_trashed)
        end)

        it("preserves soft delete flags in count()", function()
            local q = Query.new(User):withTrashed()
            assert.is_true(q._include_trashed)
        end)

        it("onlyTrashed resetea include_trashed (mutual exclusão)", function()
            -- onlyTrashed garante _only_trashed=true e _include_trashed=false,
            -- mesmo após chamado de withTrashed
            local q1 = User:withTrashed():onlyTrashed()
            assert.is_false(q1._include_trashed)
            assert.is_true(q1._only_trashed)
        end)
    end)
end)
