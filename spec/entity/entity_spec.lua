describe("Entity", function()
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")
    local Boolean = require("jade.types.boolean")

    it("creates entity with table name", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
        })
        assert.are.equal("users", User._table)
    end)

    it("registers column names", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
        })
        assert.are.equal("id", User._columns.id._name)
        assert.are.equal("name", User._columns.name._name)
    end)

    it("sets table reference on columns", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })
        assert.are.equal("users", User._columns.id._table)
    end)

    it("access column as expression via __index", function()
        local User = Entity.new("users", {
            age = Integer(),
        })
        local expr = User.age
        assert.is_not_nil(expr)
        assert.are.equal("age", expr._column)
        assert.are.equal("users", expr._table)
    end)

    it("can use expression in comparison", function()
        local User = Entity.new("users", {
            age = Integer(),
        })
        local cond = User.age:gt(18)
        assert.are.equal("age", cond.column)
        assert.are.equal(">", cond.op)
        assert.are.equal(18, cond.value)
    end)

    describe("lazy encryption loading", function()
        local was_loaded

        before_each(function()
            was_loaded = package.loaded["jade.encryption"]
            package.loaded["jade.encryption"] = nil
        end)

        local function restore_encryption()
            package.loaded["jade.encryption"] = was_loaded
        end

        it("does not require jade.encryption when no encrypted columns or config", function()
            Entity.new("plain_users", {
                id = Integer():primaryKey(),
                name = String(120),
            })
            assert.is_nil(package.loaded["jade.encryption"])
            restore_encryption()
        end)

        it("requires jade.encryption when a column is encrypted", function()
            Entity.new("secret_users", {
                id = Integer():primaryKey(),
                email = String(255):encrypted(),
            })
            assert.is_not_nil(package.loaded["jade.encryption"])
            restore_encryption()
        end)

        it("requires jade.encryption when options.encryption is present", function()
            Entity.new("cfg_users", {
                id = Integer():primaryKey(),
                name = String(120),
            }, {
                encryption = { key = "test-key" },
            })
            assert.is_not_nil(package.loaded["jade.encryption"])
            restore_encryption()
        end)
    end)
end)
