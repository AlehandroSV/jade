describe("Relations", function()
    local Relations = require("jade.entity.relations")
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")

    local User
    local Post
    local Comment

    before_each(function()
        User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
        })

        Post = Entity.new("posts", {
            id = Integer():primaryKey(),
            title = String(255),
            user_id = Integer(),
        })

        Comment = Entity.new("comments", {
            id = Integer():primaryKey(),
            body = String(),
            post_id = Integer(),
        })
    end)

    describe("ForeignKey", function()
        it("creates foreign key relation", function()
            local rel = Relations.ForeignKey(User)
            assert.are.equal("foreign_key", rel.type)
            assert.are.equal(User, rel.target)
            assert.are.equal("user_id", rel.foreign_key)
        end)

        it("uses custom foreign key", function()
            local rel = Relations.ForeignKey(User, { foreign_key = "author_id" })
            assert.are.equal("author_id", rel.foreign_key)
        end)

        it("sets onDelete and onUpdate", function()
            local rel = Relations.ForeignKey(User, { onDelete = "SET NULL" })
            assert.are.equal("SET NULL", rel.onDelete)
            assert.are.equal("CASCADE", rel.onUpdate)
        end)
    end)

    describe("hasMany", function()
        it("creates hasMany relation", function()
            local rel = Relations.hasMany(User, Post)
            assert.are.equal("hasMany", rel.type)
            assert.are.equal(Post, rel.target)
            assert.are.equal("user_id", rel.foreign_key)
        end)

        it("uses custom foreign key", function()
            local rel = Relations.hasMany(User, Post, { foreign_key = "author_id" })
            assert.are.equal("author_id", rel.foreign_key)
        end)
    end)

    describe("hasOne", function()
        it("creates hasOne relation", function()
            local rel = Relations.hasOne(User, Post)
            assert.are.equal("hasOne", rel.type)
            assert.are.equal(Post, rel.target)
            assert.are.equal("user_id", rel.foreign_key)
        end)
    end)

    describe("belongsTo", function()
        it("creates belongsTo relation", function()
            local rel = Relations.belongsTo(User)
            assert.are.equal("belongsTo", rel.type)
            assert.are.equal(User, rel.target)
            assert.are.equal("user_id", rel.foreign_key)
        end)

        it("uses custom foreign key", function()
            local rel = Relations.belongsTo(User, { foreign_key = "author_id" })
            assert.are.equal("author_id", rel.foreign_key)
        end)
    end)

    describe("self-referential relations", function()
        local Category

        before_each(function()
            Category = Entity.new("categories", {
                id = Integer():primaryKey(),
                name = String(100),
            })
        end)

        it("raises error when hasMany self-referential without explicit foreign_key", function()
            assert.has_error(function()
                Relations.hasMany(Category, Category)
            end)
        end)

        it("raises error when hasOne self-referential without explicit foreign_key", function()
            assert.has_error(function()
                Relations.hasOne(Category, Category)
            end)
        end)

        it("raises error when belongsTo self-referential without explicit foreign_key", function()
            assert.has_error(function()
                Category:belongsTo(Category)
            end)
        end)

        it("allows hasMany self-referential with explicit foreign_key", function()
            local rel = Relations.hasMany(Category, Category, { foreign_key = "parent_id" })
            assert.are.equal("parent_id", rel.foreign_key)
        end)

        it("allows hasOne self-referential with explicit foreign_key", function()
            local rel = Relations.hasOne(Category, Category, { foreign_key = "parent_id" })
            assert.are.equal("parent_id", rel.foreign_key)
        end)

        it("allows belongsTo self-referential with explicit foreign_key", function()
            local rel = Relations.belongsTo(Category, { foreign_key = "parent_id" })
            assert.are.equal("parent_id", rel.foreign_key)
        end)
    end)
end)
