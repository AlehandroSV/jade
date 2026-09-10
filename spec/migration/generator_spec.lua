describe("Migration Generator", function()
    local generator = require("jade.migration.generator")
    local Column = require("jade.schema.column")
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

    local function load_migration(source)
        local chunk, err = load_chunk(source)
        assert.is_not_nil(chunk, "generated migration must compile: " .. tostring(err))
        local mod = chunk()
        assert.is_function(mod.up)
        assert.is_function(mod.down)
        return mod
    end

    it("generates CREATE TABLE with function form (not table literal)", function()
        local columns = {
            id = Column.new(nil, "integer"):primaryKey():autoIncrement(),
            name = Column.new(nil, "string", 120):notNull(),
        }
        local sql = generator.generateCreateTable("users", columns)
        assert.is_truth(string.find(sql, "createTable", 1, true))
        assert.is_truth(string.find(sql, "function(t)", 1, true))
        assert.is_truth(string.find(sql, 't:column("id"', 1, true))
        assert.is_truth(string.find(sql, 't:column("name"', 1, true))
        assert.is_nil(string.find(sql, 'createTable("users", {', 1, true))
        assert.is_nil(string.find(sql, "t:integer", 1, true))
        assert.is_nil(string.find(sql, "t:string", 1, true))
    end)

    it("CREATE TABLE passes length and quotes string defaults", function()
        local columns = {
            role = Column.new(nil, "string", 50):default("user"),
            name = Column.new(nil, "string", 120):notNull(),
        }
        local sql = generator.generateCreateTable("users", columns)
        assert.is_truth(string.find(sql, "length = 50", 1, true))
        assert.is_truth(string.find(sql, "length = 120", 1, true))
        assert.is_truth(string.find(sql, 'default = "user"', 1, true))
    end)

    it("CREATE TABLE emits columns in deterministic sorted order", function()
        local columns = {
            zeta = Column.new(nil, "string"),
            alpha = Column.new(nil, "string"),
            id = Column.new(nil, "integer"):primaryKey():autoIncrement(),
        }
        local sql = generator.generateCreateTable("users", columns)
        local id_pos = sql:find('t:column("id"', 1, true)
        local alpha_pos = sql:find('t:column("alpha"', 1, true)
        local zeta_pos = sql:find('t:column("zeta"', 1, true)
        assert.is_not_nil(id_pos)
        assert.is_not_nil(alpha_pos)
        assert.is_not_nil(zeta_pos)
        assert.is_true(id_pos < alpha_pos, "primary key id should come first")
        assert.is_true(alpha_pos < zeta_pos, "remaining columns should be alphabetical")
    end)

    it("CREATE TABLE compiles and Schema.createTable accepts it", function()
        local columns = {
            id = Column.new(nil, "integer"):primaryKey():autoIncrement(),
            name = Column.new(nil, "string", 120):notNull(),
            email = Column.new(nil, "string", 255):unique(),
        }
        local body = generator.generateCreateTable("users", columns)

        local chunk, err = load_chunk("return function(jade)\n" .. body:gsub("Jade%.", "jade.") .. "\nend")
        assert.is_not_nil(chunk, "createTable body must compile: " .. tostring(err))
        local install = chunk()

        local called_name, called_fn
        install({
            createTable = function(name, fn)
                called_name = name
                called_fn = fn
            end,
        })

        assert.are.equal("users", called_name)
        assert.is_function(called_fn)

        local driver = mock_driver()
        local ok, exec_err = pcall(function()
            Schema.createTable(driver, called_name, called_fn)
        end)
        assert.is_true(ok, "Schema.createTable must run generated fn: " .. tostring(exec_err))
        assert.is_true(#driver.executed > 0)
        assert.is_truth(driver.executed[1].sql:match("CREATE TABLE"))
        assert.is_truth(driver.executed[1].sql:match('"id"'))
        assert.is_truth(driver.executed[1].sql:match('"name"'))
    end)

    it("generates DROP TABLE statement", function()
        local sql = generator.generateDropTable("users")
        assert.is_truth(string.find(sql, "Jade.dropTable"))
        assert.is_truth(string.find(sql, "users"))
    end)

    it("generates ADD COLUMN as Schema.addColumn signature (length is valid Lua)", function()
        local col = Column.new(nil, "string", 255)
        local sql = generator.generateAddColumn("users", "email", col)
        assert.is_truth(string.find(sql, "Jade.addColumn"))
        assert.is_truth(string.find(sql, "users"))
        assert.is_truth(string.find(sql, "email"))
        assert.is_truth(string.find(sql, '"string"', 1, true))
        assert.is_truth(string.find(sql, "length = 255", 1, true))
        -- must not pass a type constructor call as type_name
        assert.is_nil(string.find(sql, "Jade.String", 1, true))
        assert.is_nil(string.find(sql, "Jade.string", 1, true))
        -- broken double-paren form from #186
        assert.is_nil(string.find(sql, "()", 1, true) and sql:match("%(%d+%)%(%)" ))

        local chunk, err = load_chunk("return " .. sql)
        assert.is_not_nil(chunk, "ADD COLUMN line must compile: " .. tostring(err))
    end)

    it("ADD COLUMN with length compiles and matches Schema.addColumn signature", function()
        local col = Column.new(nil, "string", 255):notNull()
        local sql = generator.generateAddColumn("users", "email", col)
        assert.is_truth(sql:match('Jade%.addColumn%("users", "email", "string"'))
        assert.is_truth(sql:match("length = 255"))
        assert.is_truth(sql:match("null = false"))

        local chunk, err = load_chunk("return " .. sql)
        assert.is_not_nil(chunk, "ADD COLUMN must compile: " .. tostring(err))
    end)

    it("ADD COLUMN without length compiles", function()
        local col = Column.new(nil, "integer")
        local sql = generator.generateAddColumn("users", "age", col)
        assert.is_truth(sql:match('Jade%.addColumn%("users", "age", "integer"'))
        local chunk, err = load_chunk("return " .. sql)
        assert.is_not_nil(chunk, "ADD COLUMN without length must compile: " .. tostring(err))
    end)

    it("generates DROP COLUMN statement", function()
        local sql = generator.generateDropColumn("users", "email")
        assert.is_truth(string.find(sql, "Jade.dropColumn"))
        assert.is_truth(string.find(sql, "users"))
        assert.is_truth(string.find(sql, "email"))
    end)

    it("generates full migration from diff that loads as a chunk", function()
        local diff = {
            create_tables = {
                {
                    name = "users",
                    columns = {
                        id = Column.new(nil, "integer"):primaryKey():autoIncrement(),
                        name = Column.new(nil, "string", 120),
                    },
                },
            },
            drop_tables = {},
            add_columns = {
                {
                    table = "users",
                    column = Column.new(nil, "string", 255),
                    column_name = "email",
                },
            },
            drop_columns = {},
            modify_columns = {},
        }
        -- generateMigration reads change.column.name
        diff.add_columns[1].column.name = "email"

        local up, down = generator.generateMigration("create_users", diff)
        assert.is_truth(string.find(up, "createTable"))
        assert.is_truth(string.find(up, "function(t)", 1, true))
        assert.is_truth(string.find(up, "addColumn"))
        assert.is_truth(string.find(down, "Jade.dropTable"))

        local source = table.concat({
            'local jade = require("jade")',
            "",
            "local M = {}",
            "",
            "function M.up()",
            up,
            "end",
            "",
            "function M.down()",
            down,
            "end",
            "",
            "return M",
        }, "\n")

        local mod = load_migration(source)
        assert.is_function(mod.up)
        assert.is_function(mod.down)
    end)

    it("full migration up() executes createTable with a function", function()
        local diff = {
            create_tables = {
                {
                    name = "posts",
                    columns = {
                        id = Column.new(nil, "integer"):primaryKey():autoIncrement(),
                        title = Column.new(nil, "string", 80):notNull(),
                    },
                },
            },
            drop_tables = {},
            add_columns = {},
            drop_columns = {},
            modify_columns = {},
        }

        local up = generator.generateMigration("create_posts", diff)
        local body = up:gsub("Jade%.", "jade.")
        local chunk, err = load_chunk("return function(jade)\n" .. body .. "\nend")
        assert.is_not_nil(chunk, "up body must compile: " .. tostring(err))
        local run = chunk()

        local calls = {}
        run({
            createTable = function(name, fn)
                calls[#calls + 1] = { name = name, fn = fn }
            end,
            dropTable = function(name)
                calls[#calls + 1] = { name = name, drop = true }
            end,
        })

        assert.are.equal(1, #calls)
        assert.are.equal("posts", calls[1].name)
        assert.is_function(calls[1].fn)
    end)
end)
