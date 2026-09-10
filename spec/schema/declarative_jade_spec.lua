local Declarative = require("jade.schema.declarative")

describe("Declarative .jade parser", function()

    describe("parsedeclarativeSchema", function()
        it("parses simple model", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    email = String(255)!
                }
            ]])
            assert.is_not_nil(schema.models)
            assert.is_not_nil(schema.models.User)
            assert.are.equal("users", schema.models.User.tableName)
        end)

        it("parses multiple models", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                }
                model Post {
                    title = String(255)!
                }
            ]])
            assert.is_not_nil(schema.models.User)
            assert.is_not_nil(schema.models.Post)
        end)

        it("uses custom table name", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    table = "custom_users"
                    name = String(120)!
                }
            ]])
            assert.are.equal("custom_users", schema.models.User.tableName)
        end)

        it("returns wrapped structure compatible with parse()", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                }
            ]])
            assert.is_not_nil(schema.models)
            assert.is_not_nil(schema.options)
        end)
    end)

    describe("_parsedeclarativeField", function()
        it("parses required string", function()
            local field = Declarative._parsedeclarativeField("name", "String(120)!")
            assert.are.equal("string", field.type)
            assert.are.equal(120, field.length)
            assert.is_true(field.not_null)
        end)

        it("parses optional field", function()
            local field = Declarative._parsedeclarativeField("bio", "Text()?")
            assert.are.equal("text", field.type)
            assert.is_true(field.nullable)
        end)

        it("parses default value as string", function()
            local field = Declarative._parsedeclarativeField("role", 'String(20)!.default("user")')
            assert.are.equal("user", field.default)
        end)

        it("parses default value as boolean", function()
            local field = Declarative._parsedeclarativeField("active", "Boolean().default(true)")
            assert.is_true(field.default)
        end)

        it("parses default value as number", function()
            local field = Declarative._parsedeclarativeField("score", "Integer().default(0)")
            assert.are.equal(0, field.default)
        end)

        it("parses hasMany relation", function()
            local field = Declarative._parsedeclarativeField("posts", "hasMany(Post)")
            assert.is_not_nil(field.relation)
            assert.are.equal("hasMany", field.relation.type)
            assert.are.equal("Post", field.relation.model)
        end)

        it("parses belongsTo relation", function()
            local field = Declarative._parsedeclarativeField("author", "belongsTo(User)")
            assert.is_not_nil(field.relation)
            assert.are.equal("belongsTo", field.relation.type)
            assert.are.equal("User", field.relation.model)
        end)

        it("parses hasOne relation", function()
            local field = Declarative._parsedeclarativeField("profile", "hasOne(Profile)")
            assert.is_not_nil(field.relation)
            assert.are.equal("hasOne", field.relation.type)
            assert.are.equal("Profile", field.relation.model)
        end)

        it("generates foreign key for belongsTo", function()
            local field = Declarative._parsedeclarativeField("author", "belongsTo(User)")
            assert.are.equal("user_id", field.relation.foreign_key)
        end)

        -- #173: hasMany/hasOne FK lives on the child, named after the parent
        it("generates parent foreign key for hasMany", function()
            local field = Declarative._parsedeclarativeField("posts", "hasMany(Post)", "User")
            assert.are.equal("hasMany", field.relation.type)
            assert.are.equal("user_id", field.relation.foreign_key)
        end)

        it("generates parent foreign key for hasOne", function()
            local field = Declarative._parsedeclarativeField("profile", "hasOne(Profile)", "User")
            assert.are.equal("hasOne", field.relation.type)
            assert.are.equal("user_id", field.relation.foreign_key)
        end)

        it("generates target foreign key for belongsTo with parent", function()
            local field = Declarative._parsedeclarativeField("author", "belongsTo(User)", "Post")
            assert.are.equal("user_id", field.relation.foreign_key)
        end)
    end)

    describe("generateFullModel relation foreign_key side (#173)", function()
        it("emits parent FK for hasMany", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    posts = hasMany(Post)
                }
                model Post {
                    title = String(255)!
                    author = belongsTo(User)
                }
            ]])
            local code = Declarative.generateFullModel(schema.models.User, schema.models)
            assert.is_truthy(code:find('hasMany("Post", { foreign_key = "user_id" })', 1, true))
            assert.is_nil(code:find('foreign_key = "post_id"', 1, true))
        end)

        it("emits parent FK for hasOne", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    profile = hasOne(Profile)
                }
                model Profile {
                    bio = Text()?
                }
            ]])
            local code = Declarative.generateFullModel(schema.models.User, schema.models)
            assert.is_truthy(code:find('hasOne("Profile", { foreign_key = "user_id" })', 1, true))
            assert.is_nil(code:find('foreign_key = "profile_id"', 1, true))
        end)

        it("emits target FK for belongsTo", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                }
                model Post {
                    title = String(255)!
                    author = belongsTo(User)
                }
            ]])
            local code = Declarative.generateFullModel(schema.models.Post, schema.models)
            assert.is_truthy(code:find('belongsTo("User", { foreign_key = "user_id" })', 1, true))
        end)

        it("stores parent FK on parsed hasMany relation", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    posts = hasMany(Post)
                }
                model Post {
                    title = String(255)!
                }
            ]])
            assert.are.equal("user_id", schema.models.User.relations.posts.foreign_key)
        end)

        it("stores parent FK on parsed hasOne relation", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    profile = hasOne(Profile)
                }
                model Profile {
                    bio = Text()?
                }
            ]])
            assert.are.equal("user_id", schema.models.User.relations.profile.foreign_key)
        end)

        it("stores target FK on parsed belongsTo relation", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                }
                model Post {
                    title = String(255)!
                    author = belongsTo(User)
                }
            ]])
            assert.are.equal("user_id", schema.models.Post.relations.author.foreign_key)
        end)
    end)

    describe("generateEntity from .jade", function()
        it("generates entity with NOT NULL", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    email = String(255)!
                }
            ]])
            local entity = Declarative.generateEntity(schema.models.User)
            assert.is_not_nil(entity)
            assert.are.equal("users", entity._table)
            assert.is_not_nil(entity._columns.name)
        end)

        it("generates entity with primary key", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                }
            ]])
            local entity = Declarative.generateEntity(schema.models.User)
            assert.is_not_nil(entity._columns.id)
            assert.is_true(entity._columns.id._primary_key)
        end)

        it("preserves user-defined id", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    id = UUID()!
                    name = String(120)!
                }
            ]])
            local entity = Declarative.generateEntity(schema.models.User)
            assert.is_not_nil(entity._columns.id)
            assert.are.equal("uuid", entity._columns.id.type)
        end)

        it("generates entity with default values", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    name = String(120)!
                    active = Boolean().default(true)
                    role = String(20)!.default("user")
                }
            ]])
            local entity = Declarative.generateEntity(schema.models.User)
            assert.is_not_nil(entity._columns.active)
            assert.is_not_nil(entity._columns.role)
        end)
    end)
end)
