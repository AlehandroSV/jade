describe("Introspection - Converter", function()
    local converter = require("jade.introspection.converter")
    local Schema = require("jade.schema")

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

    it("generates migration with function-form createTable", function()
        local schema = {
            tables = {
                users = {
                    name = "users",
                    columns = {
                        id = { name = "id", type = "integer", primary_key = true, auto_increment = true },
                        name = { name = "name", type = "string", length = 120, nullable = false },
                    },
                    indexes = {},
                    foreign_keys = {},
                },
            },
        }

        local code = converter.generateMigration(schema, "test_migration")
        assert.is_truth(code:find("function M.up()", 1, true))
        assert.is_truth(code:find("function M.down()", 1, true))
        assert.is_truth(code:find("jade.createTable", 1, true))
        assert.is_truth(code:find("users", 1, true))
        assert.is_truth(code:find("function(t)", 1, true))
        assert.is_truth(code:find('t:column("id"', 1, true))
        -- invalid table-literal form must be gone
        assert.is_nil(code:find('createTable("users", {', 1, true))
        assert.is_nil(code:find("t:integer", 1, true))
        assert.is_nil(code:find("t:string", 1, true))
    end)

    it("generated migration compiles and up() uses function form", function()
        local schema = {
            tables = {
                users = {
                    name = "users",
                    columns = {
                        id = { name = "id", type = "integer", primary_key = true, auto_increment = true },
                        name = { name = "name", type = "string", length = 120, nullable = false },
                    },
                    indexes = {},
                    foreign_keys = {},
                },
            },
        }

        local code = converter.generateMigration(schema, "test_migration")
        local chunk, err = load_chunk(code)
        assert.is_not_nil(chunk, "generated migration must compile: " .. tostring(err))

        -- Execute chunk + up() against a mock jade that records createTable
        local calls = {}
        local previous = package.loaded["jade"]
        package.loaded["jade"] = {
            createTable = function(name, fn)
                calls[#calls + 1] = { name = name, fn = fn }
            end,
            dropTable = function(name)
                calls[#calls + 1] = { name = name, drop = true }
            end,
            addForeignKey = function() end,
        }
        local ok_load, mod = pcall(chunk)
        local ok_up, run_err = true, nil
        if ok_load and type(mod) == "table" and type(mod.up) == "function" then
            ok_up, run_err = pcall(mod.up)
        else
            ok_up = false
            run_err = mod
        end
        package.loaded["jade"] = previous
        assert.is_true(ok_load, "migration chunk must return module: " .. tostring(mod))
        assert.is_function(mod.up)
        assert.is_function(mod.down)
        assert.is_true(ok_up, "M.up() must not error: " .. tostring(run_err))
        assert.is_true(#calls >= 1)
        assert.are.equal("users", calls[1].name)
        assert.is_function(calls[1].fn)

        -- And Schema.createTable accepts the emitted function
        local driver = mock_driver()
        local created, create_err = pcall(function()
            Schema.createTable(driver, calls[1].name, calls[1].fn)
        end)
        assert.is_true(created, "Schema.createTable must accept generated fn: " .. tostring(create_err))
        assert.is_truth(driver.executed[1].sql:match("CREATE TABLE"))
    end)
end)
