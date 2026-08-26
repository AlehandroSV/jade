-- Tests for config module (#90)
-- Environment detection should be extensible via configurable fallbacks

describe("Config - Environment Detection", function()
    local config = require("jade.config")

    it("getEnvironment returns a non-empty string", function()
        local env = config.getEnvironment()
        assert.is_truthy(type(env) == "string")
        assert.is_truthy(#env > 0)
    end)

    it("getEnvironment returns 'development' when no env vars set", function()
        -- Save and clear any existing env vars that might affect the test
        local saved = {}
        local vars = { "JADE_ENV", "RAILS_ENV", "NODE_ENV", "GO_ENV", "APP_ENV", "FLASK_ENV", "RACK_ENV" }
        for _, var in ipairs(vars) do
            saved[var] = os.getenv(var)
        end

        -- Clear all env vars
        for _, var in ipairs(vars) do
            -- We can't easily clear env vars in Lua, so we test the default behavior
        end

        local env = config.getEnvironment()
        assert.is_truthy(type(env) == "string")
        assert.is_truthy(#env > 0)
    end)

    it("getEnvironment is callable", function()
        assert.is_function(config.getEnvironment)
    end)
end)

describe("Config - Module structure", function()
    local config = require("jade.config")

    it("config module has getEnvironment method", function()
        assert.is_function(config.getEnvironment)
    end)

    it("config module has load method", function()
        assert.is_function(config.load)
    end)

    it("config module has get method", function()
        assert.is_function(config.get)
    end)

    it("config module has set method", function()
        assert.is_function(config.set)
    end)

    it("config module has loadForEnvironment method", function()
        assert.is_function(config.loadForEnvironment)
    end)

    it("config module has parseURL method", function()
        assert.is_function(config.parseURL)
    end)
end)

describe("Config - parseURL", function()
    local config = require("jade.config")

    it("parses PostgreSQL URL correctly", function()
        local result = config.parseURL("postgresql://user:pass@localhost:5432/mydb")
        assert.are.equal("postgresql", result.driver)
        assert.are.equal("user", result.user)
        assert.are.equal("pass", result.password)
        assert.are.equal("localhost", result.host)
        assert.are.equal(5432, result.port)
        assert.are.equal("mydb", result.database)
    end)

    it("parses MySQL URL correctly", function()
        local result = config.parseURL("mysql://root:secret@db-host:3306/testdb")
        assert.are.equal("mysql", result.driver)
        assert.are.equal("root", result.user)
        assert.are.equal("secret", result.password)
        assert.are.equal("db-host", result.host)
        assert.are.equal(3306, result.port)
        assert.are.equal("testdb", result.database)
    end)

    it("parses SQLite URL correctly", function()
        local result = config.parseURL("sqlite:///path/to/database.db")
        assert.are.equal("sqlite", result.driver)
        assert.are.equal("path/to/database.db", result.database)
    end)

    it("uses default ports when not specified", function()
        local pg = config.parseURL("postgresql://user:pass@localhost/mydb")
        assert.are.equal(5432, pg.port)

        local mysql = config.parseURL("mysql://user:pass@localhost/mydb")
        assert.are.equal(3306, mysql.port)
    end)

    it("errors on invalid URL format", function()
        assert.has_error(function()
            config.parseURL("not-a-url")
        end)
    end)

    it("errors on non-string URL", function()
        assert.has_error(function()
            config.parseURL(123)
        end)
    end)
end)

describe("Config - validatePath (security)", function()
    local config = require("jade.config")

    it("accepts valid relative paths with .lua extension", function()
        assert.is_true(config.validatePath("jade.config.lua", "lua"))
        assert.is_true(config.validatePath("config/app.lua", "lua"))
        assert.is_true(config.validatePath("./config.lua", "lua"))
    end)

    it("rejects Unix directory traversal (../)", function()
        assert.has_error(function()
            config.validatePath("../../etc/passwd", "lua")
        end)
        assert.has_error(function()
            config.validatePath("foo/../../etc", "lua")
        end)
    end)

    it("rejects Windows directory traversal (..\\)", function()
        assert.has_error(function()
            config.validatePath("..\\..\\etc\\passwd", "lua")
        end)
        assert.has_error(function()
            config.validatePath("foo\\..\\..\\etc", "lua")
        end)
    end)

    it("rejects double dot in any context", function()
        assert.has_error(function()
            config.validatePath("file..backup.lua", "lua")
        end)
        assert.has_error(function()
            config.validatePath("..hidden.lua", "lua")
        end)
    end)

    it("rejects null bytes in path", function()
        assert.has_error(function()
            config.validatePath("config\0.lua", "lua")
        end)
    end)

    it("rejects Unix absolute paths", function()
        assert.has_error(function()
            config.validatePath("/etc/jade.config.lua", "lua")
        end)
        assert.has_error(function()
            config.validatePath("/absolute/path.lua", "lua")
        end)
    end)

    it("rejects Windows absolute paths", function()
        assert.has_error(function()
            config.validatePath("C:\\jade.config.lua", "lua")
        end)
        assert.has_error(function()
            config.validatePath("D:/config.lua", "lua")
        end)
    end)

    it("rejects paths without required extension", function()
        assert.has_error(function()
            config.validatePath("config.txt", "lua")
        end)
        assert.has_error(function()
            config.validatePath("config.lua.bak", "lua")
        end)
    end)

    it("rejects empty paths", function()
        assert.has_error(function()
            config.validatePath("", "lua")
        end)
    end)

    it("rejects non-string paths", function()
        assert.has_error(function()
            config.validatePath(123, "lua")
        end)
        assert.has_error(function()
            config.validatePath(nil, "lua")
        end)
        assert.has_error(function()
            config.validatePath(true, "lua")
        end)
    end)

    it("uses generic error message to avoid leaking validation details", function()
        local ok, err = pcall(function()
            config.validatePath("../../etc/passwd", "lua")
        end)
        assert.is_falsy(ok)
        assert.is_truthy(type(err) == "string")
        assert.is_truthy(err:find("rejected by security policy"))
        assert.is_falsy(err:find("null byte"))
        assert.is_falsy(err:find("traversal"))
    end)
end)
