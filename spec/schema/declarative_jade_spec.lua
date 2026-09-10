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

        it("parses field names containing underscores", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    github_id = BigInt()!
                    avatar_url = String(500)?
                    login = String(255)!
                }
            ]])
            local fields = schema.models.User.fields
            assert.is_not_nil(fields.github_id)
            assert.is_not_nil(fields.avatar_url)
            assert.is_not_nil(fields.login)
            assert.are.equal("bigint", fields.github_id.type)
            assert.are.equal("string", fields.avatar_url.type)
            assert.are.equal(500, fields.avatar_url.length)
            assert.is_true(fields.github_id.not_null)
            assert.is_nil(fields.avatar_url.not_null)
            assert.is_true(fields.avatar_url.nullable)
        end)

        it("parses snake_case relation names", function()
            local schema = Declarative.parsedeclarativeSchema([[
                model User {
                    github_id = BigInt()!
                    blog_posts = hasMany(Post)
                }
            ]])
            assert.is_not_nil(schema.models.User.fields.github_id)
            assert.is_not_nil(schema.models.User.relations.blog_posts)
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

        it("does not use target FK for hasMany (parent FK at wire time)", function()
            local field = Declarative._parsedeclarativeField("posts", "hasMany(Post)")
            -- parent FK is user_id; parser cannot know parent yet so must not force post_id
            assert.is_nil(field.relation.foreign_key)
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

    describe("wire relations (#178)", function()
        local sample = [[
            model User {
                name = String(120)!
                posts = hasMany(Post)
                profile = hasOne(Profile)
            }
            model Post {
                title = String(255)!
                author = belongsTo(User)
            }
            model Profile {
                bio = Text()?
                user = belongsTo(User)
            }
        ]]

        local function generate_all(schema)
            local entities = {}
            for name, model in pairs(schema.models) do
                entities[name] = Declarative.generateEntity(model)
            end
            Declarative.wireRelations(entities, schema.models)
            return entities
        end

        it("wires hasMany with parent foreign_key", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local entities = generate_all(schema)
            local rel = entities.User._relations.posts
            assert.is_not_nil(rel)
            assert.are.equal("hasMany", rel.type)
            assert.are.equal("posts", rel.target._table)
            assert.are.equal("user_id", rel.foreign_key)
        end)

        it("wires hasOne with parent foreign_key", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local entities = generate_all(schema)
            local rel = entities.User._relations.profiles
            assert.is_not_nil(rel)
            assert.are.equal("hasOne", rel.type)
            assert.are.equal("user_id", rel.foreign_key)
        end)

        it("wires belongsTo with target foreign_key", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local entities = generate_all(schema)
            local rel = entities.Post._relations.users
            assert.is_not_nil(rel)
            assert.are.equal("belongsTo", rel.type)
            assert.are.equal("user_id", rel.foreign_key)
            assert.are.equal("users", rel.target._table)
        end)

        it("generateEntity wires relations when entities map is provided", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local Post = Declarative.generateEntity(schema.models.Post)
            local Profile = Declarative.generateEntity(schema.models.Profile)
            local User = Declarative.generateEntity(schema.models.User, { Post = Post, Profile = Profile })
            assert.is_not_nil(User._relations.posts)
            assert.is_not_nil(User._relations.profiles)
            assert.are.equal("user_id", User._relations.posts.foreign_key)
        end)

        it("loadEntities wires User.posts and Post.author", function()
            -- os.tmpname() on Windows yields a non-writable root path (e.g. "\steg.")
            local spec_dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "spec/"
            local path = spec_dir .. "_tmp_loadentities_178.jade"
            local f = io.open(path, "w")
            if not f then
                error("cannot write temp schema: " .. path)
            end
            f:write(sample)
            f:close()

            local Jade = require("jade")
            local entities = Jade.loadEntities(path)
            os.remove(path)

            assert.is_not_nil(entities.User)
            assert.is_not_nil(entities.Post)

            local posts_rel = entities.User._relations.posts
            assert.is_not_nil(posts_rel)
            assert.are.equal("hasMany", posts_rel.type)
            assert.are.equal("user_id", posts_rel.foreign_key)

            local author_rel = entities.Post._relations.users
            assert.is_not_nil(author_rel)
            assert.are.equal("belongsTo", author_rel.type)
            assert.are.equal("user_id", author_rel.foreign_key)
        end)

        it("generateFullModel emits parent FK for hasMany/hasOne (#173)", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local code = Declarative.generateFullModel(schema.models.User, schema.models)
            assert.is_truthy(code:find('hasMany%("Post", { foreign_key = "user_id" }%)', 1, false))
            assert.is_truthy(code:find('hasOne%("Profile", { foreign_key = "user_id" }%)', 1, false))
        end)

        it("generateFullModel emits target FK for belongsTo (#173)", function()
            local schema = Declarative.parsedeclarativeSchema(sample)
            local code = Declarative.generateFullModel(schema.models.Post, schema.models)
            assert.is_truthy(code:find('belongsTo%("User", { foreign_key = "user_id" }%)', 1, false))
        end)
    end)
end)
