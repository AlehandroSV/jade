describe("Introspection - Converter", function()
    local converter = require("jade.introspection.converter")

    it("generates schema code", function()
        local schema = {
            tables = {
                users = {
                    name = "users",
                    columns = {
                        id = { name = "id", type = "integer", primary_key = true, auto_increment = true },
                        name = { name = "name", type = "string", length = 120, nullable = false },
                        email = { name = "email", type = "string", length = 255, unique = true },
                    },
                    indexes = {},
                    foreign_keys = {},
                },
            },
        }

        local code = converter.generateSchema(schema)
        assert.is_truth(code:match("jade.Entity"))
        assert.is_truth(code:match("users"))
    end)

    it("generates entity code", function()
        local table_def = {
            name = "users",
            columns = {
                id = { name = "id", type = "integer", primary_key = true },
                name = { name = "name", type = "string", length = 100 },
            },
            indexes = {},
            foreign_keys = {},
        }

        local code = converter.generateEntity("users", table_def)
        assert.is_truth(code:match("jade.Entity"))
        assert.is_truth(code:match("users"))
        assert.is_truth(code:match("id"))
        assert.is_truth(code:match("name"))
    end)

    it("generates column with string type", function()
        local col = { name = "email", type = "string", length = 255, nullable = false }
        local code = converter.generateColumn("email", col)
        assert.is_not_nil(code:match("jade.String"))
        assert.is_not_nil(code:match("255"))
        assert.is_not_nil(code:match("notNull"))
    end)

    it("generates column with integer type", function()
        local col = { name = "id", type = "integer", primary_key = true }
        local code = converter.generateColumn("id", col)
        assert.is_truth(code:match("jade.Integer()"))
        assert.is_truth(code:match(":primaryKey()"))
    end)

    it("generates column with default value", function()
        local col = { name = "active", type = "boolean", default = "true" }
        local code = converter.generateColumn("active", col)
        assert.is_not_nil(code:match("default"))
        assert.is_not_nil(code:match("true"))
    end)

    it("generates migration code", function()
        local schema = {
            tables = {
                users = {
                    name = "users",
                    columns = {
                        id = { name = "id", type = "integer", primary_key = true },
                    },
                    indexes = {},
                    foreign_keys = {},
                },
            },
        }

        local code = converter.generateMigration(schema, "test_migration")
        assert.is_truth(code:match("function M.up()"))
        assert.is_truth(code:match("function M.down()"))
        assert.is_truth(code:match("jade.createTable"))
        assert.is_truth(code:match("users"))
    end)
end)
