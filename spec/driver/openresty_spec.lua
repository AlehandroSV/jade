-- Tests for OpenResty driver registration and context module (#92)

describe("OpenResty Driver Registration", function()
    local drivers = require("jade.driver")

    it("registers openresty driver", function()
        assert.is_truthy(drivers.get)
        -- Should not error when getting the driver
        local ok, err = pcall(function()
            drivers.get("openresty")
        end)
        -- May fail if ngx is not available, but should be registered
        assert.is_true(ok or string.find(tostring(err), "ngx"))
    end)

    it("registers postgresql driver", function()
        local driver = drivers.get("postgresql")
        assert.is_truthy(driver)
    end)

    it("registers mysql driver", function()
        local driver = drivers.get("mysql")
        assert.is_truthy(driver)
    end)

    it("registers sqlite driver", function()
        local driver = drivers.get("sqlite")
        assert.is_truthy(driver)
    end)
end)

describe("Context Module", function()
    local context = require("jade.util.context")

    it("gets and sets values", function()
        context.set("test_key", "test_value")
        assert.are.equal("test_value", context.get("test_key"))
    end)

    it("returns nil for unset keys", function()
        assert.is_nil(context.get("nonexistent_key_" .. os.time()))
    end)

    it("clears all context", function()
        context.set("key1", "value1")
        context.set("key2", "value2")
        context.clear()
        assert.is_nil(context.get("key1"))
        assert.is_nil(context.get("key2"))
    end)

    it("overwrites existing values", function()
        context.set("overwrite_key", "old")
        context.set("overwrite_key", "new")
        assert.are.equal("new", context.get("overwrite_key"))
        context.clear()
    end)
end)
