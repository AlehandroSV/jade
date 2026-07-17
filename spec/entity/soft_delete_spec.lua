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
end)
