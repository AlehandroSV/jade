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

    describe("generateMigration", function()
        local load_chunk = loadstring or load

        local function mock_driver()
            local executed = {}
            local driver = {
                executed = executed,
                mapType = function(_, column)
                    local map = {
                        string = "TEXT",
                        text = "TEXT",
                        integer = "INTEGER",
                        bigint = "INTEGER",
                        float = "REAL",
                        decimal = "REAL",
                        boolean = "INTEGER",
                        timestamp = "TEXT",
                        date = "TEXT",
                        uuid = "TEXT",
                        json = "TEXT",
                    }
                    return map[column.type] or "TEXT"
                end,
                supportsAutoIncrement = function()
                    return true
                end,
                autoIncrementKeyword = function()
                    return "AUTOINCREMENT"
                end,
                dropTableCascade = function()
                    return false
                end,
                execute = function(_, sql, bindings)
                    executed[#executed + 1] = { sql = sql, bindings = bindings }
                    return {}
                end,
            }
            return driver
        end

        it("returns Lua source (string), not a runtime migration object", function()
            local schema = Declarative.parse({
                User = { name = "string" },
            })
            local code = Declarative.generateMigration(schema, "create_users")
            assert.are.equal("string", type(code))
        end)

        it("emits function-form createTable using t:column", function()
            local schema = Declarative.parse({
                User = {
                    name = "string(120)",
                    email = { type = "string", length = 255, unique = true, not_null = true },
                },
            })
            local code = Declarative.generateMigration(schema, "create_users")
            assert.is_truth(code:find("function M.up()", 1, true))
            assert.is_truth(code:find("function M.down()", 1, true))
            assert.is_truth(code:find("jade.createTable", 1, true))
            assert.is_truth(code:find("function(t)", 1, true))
            assert.is_truth(code:find('t:column("id"', 1, true))
            assert.is_truth(code:find('t:column("name"', 1, true))
            assert.is_truth(code:find("primary_key", 1, true))
            -- invalid Table fluent type methods
            assert.is_nil(code:find("t:integer", 1, true))
            assert.is_nil(code:find("t:string", 1, true))
            assert.is_nil(code:find('createTable("users", {', 1, true))
        end)

        it("generated migration compiles and runs against Schema.createTable", function()
            local Schema = require("jade.schema")
            local schema = Declarative.parse({
                User = {
                    name = "string(120)",
                    email = { type = "string", length = 255, unique = true, not_null = true },
                    timestamps = false,
                },
            })
            local code = Declarative.generateMigration(schema, "create_users")
            local chunk, err = load_chunk(code)
            assert.is_not_nil(chunk, "generated migration must compile: " .. tostring(err))

            local calls = {}
            local previous = package.loaded["jade"]
            package.loaded["jade"] = {
                createTable = function(name, fn)
                    calls[#calls + 1] = { name = name, fn = fn }
                end,
                dropTable = function(name)
                    calls[#calls + 1] = { name = name, drop = true }
                end,
            }
            -- chunk() runs `local jade = require("jade")` — mock must be in place
            local ok_load, mod_or_err = pcall(chunk)
            local ok_up, run_err = true, nil
            local mod = mod_or_err
            if ok_load and type(mod) == "table" and type(mod.up) == "function" then
                ok_up, run_err = pcall(mod.up)
            else
                ok_up = false
                run_err = mod_or_err
            end
            package.loaded["jade"] = previous
            assert.is_true(ok_load, "migration chunk must return module: " .. tostring(mod_or_err))
            assert.is_function(mod.up)
            assert.is_function(mod.down)
            assert.is_true(ok_up, "M.up() must not error: " .. tostring(run_err))
            assert.is_true(#calls >= 1)
            assert.is_function(calls[1].fn)

            local driver = mock_driver()
            local created, create_err = pcall(function()
                Schema.createTable(driver, calls[1].name, calls[1].fn)
            end)
            assert.is_true(created, "Schema.createTable must accept generated fn: " .. tostring(create_err))
            assert.is_truth(driver.executed[1].sql:match("CREATE TABLE"))
            assert.is_truth(driver.executed[1].sql:match('"name"'))
            assert.is_truth(driver.executed[1].sql:match('"email"'))
        end)
    end)
end)
