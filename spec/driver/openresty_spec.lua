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

    it("isolates context between coroutines", function()
        -- Test that coroutines have isolated contexts
        local co1_results = {}
        local co2_results = {}

        local co1 = coroutine.create(function()
            context.set("co_key", "co1_value")
            co1_results.value = context.get("co_key")
            coroutine.yield()
            co1_results.after_yield = context.get("co_key")
        end)

        local co2 = coroutine.create(function()
            context.set("co_key", "co2_value")
            co2_results.value = context.get("co_key")
        end)

        -- Run co1 first
        coroutine.resume(co1)
        -- Run co2
        coroutine.resume(co2)
        -- Resume co1
        coroutine.resume(co1)

        -- Each coroutine should have its own value
        assert.are.equal("co1_value", co1_results.value)
        assert.are.equal("co1_value", co1_results.after_yield)
        assert.are.equal("co2_value", co2_results.value)

        -- Clean up
        context.clear()
    end)
end)
