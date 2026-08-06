describe("HABTM Pivot SQL Injection Prevention", function()
    local Entity = require("jade.entity")
    local Integer = require("jade.types.integer")
    local String = require("jade.types.string")

    -- Mock driver that captures the SQL and bindings passed to execute
    local MockDriver
    local last_sql
    local last_bindings

    before_each(function()
        last_sql = nil
        last_bindings = nil

        MockDriver = setmetatable({}, { __index = require("jade.driver.base") })
        MockDriver._driver_type = "mock"

        function MockDriver:execute(sql, bindings)
            last_sql = sql
            last_bindings = bindings or {}
            return {{ id = 1 }}
        end

        function MockDriver:quoteIdentifier(name)
            return '"' .. name:gsub('"', '""') .. '"'
        end
    end)

    it("rejects invalid characters in join_table name", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
            name = String(120),
        })

        local Tag = Entity.new("tags", {
            id = Integer():primaryKey(),
            name = String(120),
        })

        User:hasAndBelongsToMany(Tag, {
            join_table = "users_tags; DROP TABLE users",
            source_foreign_key = "user_id",
            target_foreign_key = "tag_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 1 })
        User._driver = MockDriver

        assert.has_error(function()
            User:_resolveChildren({
                tags = { connect = { id = 5 } }
            }, user_instance)
        end)
    end)

    it("rejects semicolons in foreign key names", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })

        local Post = Entity.new("posts", {
            id = Integer():primaryKey(),
        })

        User:hasAndBelongsToMany(Post, {
            join_table = "user_post",
            source_foreign_key = "user_id; DROP TABLE posts",
            target_foreign_key = "post_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 1 })
        User._driver = MockDriver

        assert.has_error(function()
            User:_resolveChildren({
                posts = { connect = { id = 10 } }
            }, user_instance)
        end)
    end)

    it("uses ? placeholders instead of $1 $2 syntax", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })

        local Category = Entity.new("categories", {
            id = Integer():primaryKey(),
            name = String(120),
        })

        User:hasAndBelongsToMany(Category, {
            join_table = "user_categories",
            source_foreign_key = "user_id",
            target_foreign_key = "category_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 42 })
        User._driver = MockDriver

        User:_resolveChildren({
            categories = { connect = { ids = { 7, 13 } } }
        }, user_instance)

        -- Should use ? placeholders, not $1 $2
        assert.is_true(last_sql:find("?") ~= nil, "SQL should contain ? placeholders")
        assert.is_false(last_sql:find("$1") ~= nil, "SQL should NOT contain $1 placeholders")
        assert.is_false(last_sql:find("$2") ~= nil, "SQL should NOT contain $2 placeholders")
    end)

    it("quotes identifiers in generated SQL", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })

        local Item = Entity.new("items", {
            id = Integer():primaryKey(),
        })

        User:hasAndBelongsToMany(Item, {
            join_table = "user_items",
            source_foreign_key = "user_id",
            target_foreign_key = "item_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 99 })
        User._driver = MockDriver

        User:_resolveChildren({
            items = { connect = { id = 3 } }
        }, user_instance)

        -- Identifiers should be quoted by driver:quoteIdentifier
        assert.is_true(last_sql:find('"user_items"') ~= nil, "join_table should be quoted")
        assert.is_true(last_sql:find('"user_id"') ~= nil, "source FK should be quoted")
        assert.is_true(last_sql:find('"item_id"') ~= nil, "target FK should be quoted")
    end)

    it("accepts valid identifier names without raising errors", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })

        local Role = Entity.new("roles", {
            id = Integer():primaryKey(),
        })

        User:hasAndBelongsToMany(Role, {
            join_table = "user_roles",
            source_foreign_key = "user_id",
            target_foreign_key = "role_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 5 })
        User._driver = MockDriver

        -- Should NOT raise an error for valid identifiers
        local ok, err = pcall(function()
            User:_resolveChildren({
                roles = { connect = { id = 2 } }
            }, user_instance)
        end)

        assert.is_true(ok, "Should succeed with valid identifiers")
        assert.is_nil(err)
    end)

    it("passes binding values as parameters (not interpolated)", function()
        local User = Entity.new("users", {
            id = Integer():primaryKey(),
        })

        local Permission = Entity.new("permissions", {
            id = Integer():primaryKey(),
        })

        User:hasAndBelongsToMany(Permission, {
            join_table = "user_permissions",
            source_foreign_key = "user_id",
            target_foreign_key = "permission_id",
        })

        local user_instance = require("jade.entity.instance").new(User, { id = 123 })
        User._driver = MockDriver

        User:_resolveChildren({
            permissions = { connect = { id = 456 } }
        }, user_instance)

        -- Bindings should be parameterized, not embedded in SQL
        -- Check count via length
        assert.is_not_nil(last_bindings[1], "Should have first binding")
        assert.is_not_nil(last_bindings[2], "Should have second binding")
        assert.is_true(last_bindings[1] == 123, "First binding should be parent ID")
        assert.is_true(last_bindings[2] == 456, "Second binding should be target ID")
    end)
end)
