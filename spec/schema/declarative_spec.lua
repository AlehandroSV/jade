describe("Declarative Schema", function()
    local Declarative = require("jade.schema.declarative")

    describe("parseType", function()
        it("parses simple type", function()
            local col = Declarative.parseType("string")
            assert.are.equal("string", col.type)
            assert.are.equal(255, col.length)
        end)

        it("parses type with length", function()
            local col = Declarative.parseType("string(120)")
            assert.are.equal("string", col.type)
            assert.are.equal(120, col.length)
        end)

        it("parses decimal with precision", function()
            local col = Declarative.parseType("decimal(10,2)")
            assert.are.equal("decimal", col.type)
            assert.are.equal(10, col.precision)
            assert.are.equal(2, col.scale)
        end)

        it("parses integer type", function()
            local col = Declarative.parseType("integer")
            assert.are.equal("integer", col.type)
        end)

        it("parses boolean type", function()
            local col = Declarative.parseType("boolean")
            assert.are.equal("boolean", col.type)
        end)
    end)

    describe("parseField", function()
        it("parses string field definition", function()
            local field = Declarative.parseField("name", "string")
            assert.are.equal("name", field.name)
            assert.are.equal("string", field.type)
            assert.are.equal(255, field.length)
        end)

        it("parses table field definition", function()
            local field = Declarative.parseField("email", {
                type = "string",
                length = 100,
                unique = true,
                not_null = true,
            })
            assert.are.equal("email", field.name)
            assert.are.equal("string", field.type)
            assert.are.equal(100, field.length)
            assert.is_true(field.unique)
            assert.is_true(field.not_null)
        end)

        it("parses primary key field", function()
            local field = Declarative.parseField("id", {
                type = "integer",
                primary_key = true,
            })
            assert.is_true(field.primary_key)
        end)

        it("parses default value", function()
            local field = Declarative.parseField("active", {
                type = "boolean",
                default = true,
            })
            assert.are.same(true, field.default)
        end)

        it("parses default_now", function()
            local field = Declarative.parseField("created_at", {
                type = "timestamp",
                default_now = true,
            })
            assert.is_true(field.default_now)
        end)

        it("parses references", function()
            local field = Declarative.parseField("user_id", {
                type = "integer",
                references = { table = "users", column = "id" },
            })
            assert.are.same({ table = "users", column = "id" }, field.references)
        end)
    end)

    describe("parseModel", function()
        it("parses simple model", function()
            local model = Declarative.parseModel("User", {
                name = "string",
                email = "string(100)",
            })
            assert.are.equal("User", model.name)
            assert.are.equal("users", model.tableName)
            assert.is_not_nil(model.fields.name)
            assert.is_not_nil(model.fields.email)
            assert.is_not_nil(model.fields.id)
            assert.is_not_nil(model.fields.created_at)
            assert.is_not_nil(model.fields.updated_at)
        end)

        it("uses custom table name", function()
            local model = Declarative.parseModel("User", {
                table = "people",
                name = "string",
            })
            assert.are.equal("people", model.tableName)
        end)

        it("disables timestamps", function()
            local model = Declarative.parseModel("User", {
                timestamps = false,
                name = "string",
            })
            assert.is_nil(model.fields.created_at)
            assert.is_nil(model.fields.updated_at)
        end)

        it("parses relations", function()
            local model = Declarative.parseModel("Post", {
                title = "string",
                relations = {
                    user = { type = "belongsTo", model = "User" },
                },
            })
            assert.is_not_nil(model.relations.user)
            assert.are.equal("belongsTo", model.relations.user.type)
        end)

        it("parses validations", function()
            local model = Declarative.parseModel("User", {
                name = "string",
                validations = {
                    name = { presence = true, length = { min = 1, max = 100 } },
                },
            })
            assert.is_not_nil(model.validations.name)
            assert.is_true(model.validations.name.presence)
        end)
    end)

    describe("parse", function()
        it("parses complete schema", function()
            local schema = Declarative.parse({
                User = {
                    name = "string",
                    email = "string(100)",
                },
                Post = {
                    title = "string",
                    body = "text",
                    relations = {
                        user = { type = "belongsTo", model = "User" },
                    },
                },
            })
            assert.is_not_nil(schema.models.User)
            assert.is_not_nil(schema.models.Post)
            assert.are.equal("users", schema.models.User.tableName)
            assert.are.equal("posts", schema.models.Post.tableName)
        end)
    end)

    describe("conventions", function()
        it("pluralizes table name", function()
            local table_name = Declarative.conventions.tableName("User")
            assert.are.equal("users", table_name)
        end)

        it("generates foreign key name", function()
            local fk_name = Declarative.conventions.foreignKey("User")
            assert.are.equal("user_id", fk_name)
        end)

        it("generates primary key definition", function()
            local pk = Declarative.conventions.primaryKey()
            assert.are.equal("integer", pk.type)
            assert.is_true(pk.primary_key)
            assert.is_true(pk.auto_increment)
        end)

        it("generates timestamps definition", function()
            local ts = Declarative.conventions.timestamps()
            assert.is_not_nil(ts.created_at)
            assert.is_not_nil(ts.updated_at)
            assert.is_true(ts.created_at.default_now)
            assert.is_true(ts.updated_at.default_now)
        end)
    end)

    describe("generateEntity", function()
        it("generates entity from model", function()
            local model = Declarative.parseModel("User", {
                name = "string",
                email = "string(100)",
            })
            local entity = Declarative.generateEntity(model)
            assert.are.equal("users", entity._table)
            assert.is_not_nil(entity._columns.name)
            assert.is_not_nil(entity._columns.email)
            assert.is_not_nil(entity._columns.id)
        end)
    end)

    describe("define", function()
        it("defines schema with builder", function()
            local schema = Declarative.define(function(d)
                d:model("User", {
                    name = "string",
                    email = "string(100)",
                }):model("Post", {
                    title = "string",
                    body = "text",
                })
            end)
            assert.is_not_nil(schema.models.User)
            assert.is_not_nil(schema.models.Post)
        end)
    end)

    describe("generateFullModel relation FK side (#173)", function()
        it("uses parent FK for hasMany from table-format relations", function()
            local model = Declarative.parseModel("User", {
                name = "string",
                relations = {
                    posts = { type = "hasMany", model = "Post" },
                },
            })
            local code = Declarative.generateFullModel(model)
            assert.is_truthy(code:find('hasMany("Post", { foreign_key = "user_id" })', 1, true))
            assert.is_nil(code:find('foreign_key = "post_id"', 1, true))
        end)

        it("uses parent FK for hasOne from table-format relations", function()
            local model = Declarative.parseModel("User", {
                name = "string",
                relations = {
                    profile = { type = "hasOne", model = "Profile" },
                },
            })
            local code = Declarative.generateFullModel(model)
            assert.is_truthy(code:find('hasOne("Profile", { foreign_key = "user_id" })', 1, true))
        end)

        it("uses target FK for belongsTo from table-format relations", function()
            local model = Declarative.parseModel("Post", {
                title = "string",
                relations = {
                    user = { type = "belongsTo", model = "User" },
                },
            })
            local code = Declarative.generateFullModel(model)
            assert.is_truthy(code:find('belongsTo("User", { foreign_key = "user_id" })', 1, true))
        end)
    end)
end)
