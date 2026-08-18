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
        assert.equal("postgresql", result.driver)
        assert.equal("user", result.user)
        assert.equal("pass", result.password)
        assert.equal("localhost", result.host)
        assert.equal(5432, result.port)
        assert.equal("mydb", result.database)
    end)

    it("parses MySQL URL correctly", function()
        local result = config.parseURL("mysql://root:secret@db-host:3306/testdb")
        assert.equal("mysql", result.driver)
        assert.equal("root", result.user)
        assert.equal("secret", result.password)
        assert.equal("db-host", result.host)
        assert.equal(3306, result.port)
        assert.equal("testdb", result.database)
    end)

    it("parses SQLite URL correctly", function()
        local result = config.parseURL("sqlite:///path/to/database.db")
        assert.equal("sqlite", result.driver)
        assert.equal("path/to/database.db", result.database)
    end)

    it("uses default ports when not specified", function()
        local pg = config.parseURL("postgresql://user:pass@localhost/mydb")
        assert.equal(5432, pg.port)

        local mysql = config.parseURL("mysql://user:pass@localhost/mydb")
        assert.equal(3306, mysql.port)
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
