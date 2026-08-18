--- Tests for the Jade Plugin System
--- Uses the project's native assert patterns: assert.is_true(), assert.is_false(), etc.

local Hooks = require("jade.plugin.hooks")
local Loader = require("jade.plugin.loader")

-- Load wrapper plugins to validate metadata
local CallbacksPlugin     = require("jade.plugin.callbacks")
local SoftDeletePlugin    = require("jade.plugin.soft_delete")
local OptimisticLockPlugin = require("jade.plugin.optimistic_lock")
local AuditPlugin         = require("jade.plugin.audit")
local EncryptionPlugin    = require("jade.plugin.encryption")
local CachePlugin         = require("jade.plugin.cache")

---------------------------------------------------------------------------
-- Helpers: make_plugin factory (creates minimal valid plugins)
---------------------------------------------------------------------------
local function make_plugin(name_, version_, setup_fn_, teardown_fn_)
    return {
        name       = name_,
        version    = version_,
        description = "Test plugin: " .. name_,
        setup      = setup_fn_ or function() return true end,
        teardown   = teardown_fn_ or function() end,
        hooks      = nil,
    }
end

local plugin_init = require("jade.plugin")

---------------------------------------------------------------------------
-- Test: plugin.base
---------------------------------------------------------------------------
describe("plugin.base", function()

    it("validate accepts correct plugin", function()
        local mod = require("jade.plugin.base")
        local ok, err = mod.validate({ name = "test", version = "1.0.0" })
        assert.is_true(ok)
    end)

    it("validate rejects missing name", function()
        local mod = require("jade.plugin.base")
        local ok, err = mod.validate({ version = "1.0.0" })
        assert.is_false(ok)
    end)

    it("validate rejects missing version", function()
        local mod = require("jade.plugin.base")
        local ok, err = mod.validate({ name = "test" })
        assert.is_false(ok)
    end)

    it("validate rejects non-table", function()
        local mod = require("jade.plugin.base")
        local ok, err = mod.validate("not a table")
        assert.is_false(ok)
    end)

    it("new creates default plugin with setup/teardown", function()
        local mod = require("jade.plugin.base")
        local p = mod.new({ name = "demo", version = "0.1.0" })
        assert.are.equal("demo", p.name)
        assert.are.equal("0.1.0", p.version)
        assert.is_function(p.setup)
        assert.is_function(p.teardown)
    end)
end)

---------------------------------------------------------------------------
-- Test: plugin.hooks
---------------------------------------------------------------------------
describe("plugin.hooks", function()

    before_each(function()
        Hooks.clear()
    end)

    it("register adds handler to registry", function()
        local fired_count = 0
        Hooks.register("beforeQuery", function() fired_count = fired_count + 1 end)
        Hooks.fire("beforeQuery")
        assert.are.equal(1, fired_count, "single handler should have fired once")
    end)

    it("register groups by source", function()
        local alpha_fired = false
        Hooks.register("afterQuery", function() alpha_fired = true end, { plugin = "alpha" })

        local beta_fired = false
        Hooks.register("afterQuery", function() beta_fired = true end, { plugin = "beta" })

        Hooks.fire("afterQuery")
        assert.is_true(alpha_fired)
        assert.is_true(beta_fired)
    end)

    it("fire stops on error", function()
        local count_ = 0
        Hooks.register("beforeCreate", function() count_ = count_ + 1 end)
        Hooks.register("beforeCreate", function() error("boom") end)
        Hooks.register("beforeCreate", function() count_ = count_ + 100 end)

        Hooks.fire("beforeCreate")
        assert.are.equal(1, count_, "third handler should not run after error")
    end)

    it("unregister removes hooks for a plugin", function()
        local ran_alpha = false
        Hooks.register("extendEntity", function() ran_alpha = true end, { plugin = "test-unreg" })
        Hooks.unregister("test-unreg")
        Hooks.fire("extendEntity")
        assert.is_false(ran_alpha, "unregistered plugin's hooks should not fire")
    end)

    it("fire fires all beforeQuery handlers", function()
        local fired_count = 0
        Hooks.register("beforeQuery", function() fired_count = fired_count + 1 end)
        Hooks.register("afterQuery", function() fired_count = fired_count + 10 end)
        Hooks.fire("beforeQuery")
        assert.are.equal(1, fired_count)
    end)

    it("decorateDriver wraps execute with hooks", function()
        Hooks.clear()
        local log = {}
        Hooks.register("beforeQuery", function() table.insert(log, "bq") end)
        Hooks.register("afterQuery", function() table.insert(log, "aq") end)
        local drv = {
            execute = function(self_, sql, bindings)
                return sql == "SELECT 1" and { id = 1 } or {}
            end,
        }
        Hooks.decorateDriver(drv):execute("SELECT 1")
        assert.are.equal(2, #log)
        assert.are.equal("bq", log[1])
        assert.are.equal("aq", log[2])
    end)

    it("fireAround chains around hooks", function()
        Hooks.register("aroundSave", function(ctx_)
            return ctx_.next()
        end)

        local result_ = Hooks.fireAround({}, "save", function() return "core-result" end)
        assert.are.equal("core-result", result_)
    end)

    it("fireAround empty runs core fn directly", function()
        Hooks.clear()
        local result_ = Hooks.fireAround({}, "update", function() return 42 end)
        assert.are.equal(42, result_)
    end)

    it("decorateDriver wraps execute with before/after hooks", function()
        Hooks.clear()

        local ctx_log = {}
        Hooks.register("beforeQuery", function(ctx_)
            table.insert(ctx_log, { type = "before", sql = ctx_.sql })
        end)

        Hooks.register("afterQuery", function(ctx_)
            table.insert(ctx_log, { type = "after", rows = #ctx_.rows })
        end)

        local driver_ = {
            execute = function(_, sql, bindings)
                if sql == "SELECT 1" then return { id = 1 } end
                return {}
            end,
        }

        Hooks.decorateDriver(driver_):execute("SELECT 1")
        assert.are.equal(2, #ctx_log, "should have both before and after logged")
        assert.are.equal("before", ctx_log[1].type)
        assert.are.equal("after", ctx_log[2].type)
    end)
end)

---------------------------------------------------------------------------
-- Test: plugin.init (API)
---------------------------------------------------------------------------
describe("plugin.init", function()

    before_each(function()
        Hooks.clear()
    end)

    it("use installs a valid plugin", function()
        local setup_called = false
        local plugin_ = make_plugin("test-use", "0.5.0", function(self_, opts_)
            setup_called = true
            return true
        end)

        local ok, err = plugin_init.use(plugin_, { ttl = 300 })
        assert.is_true(ok)
        assert.is_true(setup_called)
    end)

    it("use rejects duplicate install", function()
        local plugin_ = make_plugin("test-dup", "0.1.0")

        local ok1, _ = plugin_init.use(plugin_)
        assert.is_true(ok1)

        local ok2, err2 = plugin_init.use(plugin_)
        assert.is_false(ok2)
        assert.is_truthy(string.find(err2, "already installed"))
    end)

    it("use fails on invalid plugin", function()
        local bad_ = { version = "1.0.0" } -- no name
        local ok, err = plugin_init.use(bad_)
        assert.is_false(ok)
    end)

    it("unloadPlugin removes and calls teardown", function()
        local teardown_called = false
        local plugin_ = make_plugin("test-unload", "0.1.0",
            function() return true end,
            function() teardown_called = true end
        )

        plugin_init.use(plugin_)
        assert.is_true(plugin_init.hasPlugin("test-unload"))

        local ok, _ = plugin_init.unloadPlugin("test-unload")
        assert.is_true(ok)
        assert.is_true(teardown_called)
        assert.is_false(plugin_init.hasPlugin("test-unload"))
    end)

    it("listPlugins returns name->version map", function()
        local plugin_ = make_plugin("test-list", "2.0.0-rc1")
        plugin_init.use(plugin_)
        local list_ = plugin_init.listPlugins()
        assert.are.equal("2.0.0-rc1", list_["test-list"])
    end)

    it("hooks() returns HookRegistry reference", function()
        local reg_ = plugin_init.hooks()
        assert.is_truthy(reg_ == Hooks)
    end)
end)

---------------------------------------------------------------------------
-- Test: plugin.loader
---------------------------------------------------------------------------
describe("plugin.loader", function()

    it("loadAll with empty/nil config returns empty table", function()
        local jade_mock = { use = function() return true, nil end }
        local results_ = Loader.loadAll(jade_mock, nil)
        assert.is_nil(next(results_))

        results_ = Loader.loadAll(jade_mock, {})
        assert.is_nil(next(results_))
    end)

    it("find builtin resolves registered names", function()
        local mod_ = Loader.find({ name = "soft-delete", source = "builtin" })
        assert.is_not_nil(mod_)
        assert.are.equal("soft-delete", mod_.name)
    end)

    it("find builtin rejects unregistered name", function()
        local mod_, err_ = Loader.find({ name = "nonexistent", source = "builtin" })
        assert.is_nil(mod_)
        assert.is_not_nil(err_)
    end)

    it("loadAll filters failed plugins", function()
        local call_log = {}
        local jade_mock = {
            use = function(plugin_, opts_)
                table.insert(call_log, plugin_.name)
                return true, nil
            end,
        }

        Loader.loadAll(jade_mock, {
            { name = "soft-delete" },
            { name = "cache", ttl = 600 },
        })

        assert.are.equal(2, #call_log)
        assert.are.equal("soft-delete", call_log[1])
        assert.are.equal("cache", call_log[2])
    end)

    it("rockspec builds correct luarock name", function()
        local rock_ = Loader._rockspec("audit")
        assert.are.equal("jade-plugin-audit", rock_)
    end)
end)

---------------------------------------------------------------------------
-- Test: wrapper plugins -> metadata checks
---------------------------------------------------------------------------
describe("wrapper plugins - callbacks", function()
    it("has correct metadata", function()
        assert.are.equal("callbacks", CallbacksPlugin.name)
        assert.is_truthy(CallbacksPlugin.version ~= "")
        assert.is_function(CallbacksPlugin.setup)
        assert.is_function(CallbacksPlugin.teardown)
        assert.is_not_nil(CallbacksPlugin.hooks)
    end)
end)

describe("wrapper plugins - soft-delete", function()
    it("has correct metadata", function()
        assert.are.equal("soft-delete", SoftDeletePlugin.name)
        assert.is_truthy(SoftDeletePlugin.version ~= "")
        assert.is_function(SoftDeletePlugin.setup)
        assert.is_function(SoftDeletePlugin.teardown)
        assert.is_not_nil(SoftDeletePlugin.hooks)
    end)
end)

describe("wrapper plugins - optimistic-lock", function()
    it("has correct metadata", function()
        assert.are.equal("optimistic-lock", OptimisticLockPlugin.name)
        assert.is_truthy(OptimisticLockPlugin.version ~= "")
        assert.is_not_nil(OptimisticLockPlugin.hooks)
        assert.is_function(OptimisticLockPlugin.install)
    end)
end)

describe("wrapper plugins - audit", function()
    it("has correct metadata", function()
        assert.are.equal("audit", AuditPlugin.name)
        assert.is_truthy(AuditPlugin.version ~= "")
        assert.is_function(AuditPlugin.query)
    end)
end)

describe("wrapper plugins - encryption", function()
    it("has correct metadata", function()
        assert.are.equal("encryption", EncryptionPlugin.name)
        assert.is_truthy(EncryptionPlugin.version ~= "")
        assert.is_function(EncryptionPlugin.setup)
    end)
end)

describe("wrapper plugins - cache", function()
    it("has correct metadata and convenience methods", function()
        assert.are.equal("cache", CachePlugin.name)
        assert.is_truthy(CachePlugin.version ~= "")
        assert.is_function(CachePlugin.get)
        assert.is_function(CachePlugin.set)
        assert.is_function(CachePlugin.delete)
    end)
end)
