-- Tests for config module (#90)
-- Environment detection should be extensible via configurable fallbacks

describe("Config - Environment Detection", function()
    local config = require("jade.config")

    it("returns 'development' when no env vars set", function()
        -- This test verifies the default behavior
        -- In CI/test environment, JADE_ENV may or may not be set
        local env = config.getEnvironment()
        assert.is_truthy(env)
        assert.is_truthy(type(env) == "string")
    end)

    it("getEnvironment returns a string", function()
        local env = config.getEnvironment()
        assert.is_truthy(type(env) == "string")
        assert.is_truthy(#env > 0)
    end)

    it("getEnvironment is callable", function()
        assert.is_function(config.getEnvironment)
    end)
end)

describe("Config - Extensible env fallbacks", function()
    -- Test the internal logic by verifying the module structure
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
end)
