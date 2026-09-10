describe("Plugin system", function()
    local Jade = require("jade")
    local plugin = require("jade.plugin")
    local loader = require("jade.plugin.loader")
    local Hooks = require("jade.plugin.hooks")

    local function reset()
        for name in pairs(plugin.listPlugins()) do
            plugin.unloadPlugin(name)
        end
        Hooks.clear()
    end

    before_each(function()
        reset()
    end)

    describe("loader.extractOptions", function()
        it("uses nested options table when present", function()
            local opts = loader.extractOptions({ name = "cache", options = { ttl = 10 } })
            assert.are.equal(10, opts.ttl)
        end)

        it("treats top-level keys as options", function()
            local opts = loader.extractOptions({ name = "cache", ttl = 300, max_size = 5 })
            assert.are.equal(300, opts.ttl)
            assert.are.equal(5, opts.max_size)
            assert.is_nil(opts.name)
        end)

        it("ignores reserved keys", function()
            local opts = loader.extractOptions({
                name = "x",
                source = "builtin",
                path = "./p",
                spec = "s",
                foo = 1,
            })
            assert.is_nil(opts.source)
            assert.is_nil(opts.path)
            assert.are.equal(1, opts.foo)
        end)
    end)

    describe("loader.loadAll", function()
        it("loads builtin cache with top-level ttl option", function()
            local results = loader.loadAll(Jade, {
                { name = "cache", ttl = 60 },
            })
            assert.is_true(results.cache.ok)
            assert.is_true(plugin.hasPlugin("cache"))
        end)

        it("reports unknown plugin name", function()
            local results = loader.loadAll(Jade, {
                { name = "does-not-exist" },
            })
            assert.is_false(results["does-not-exist"].ok)
        end)

        it("loads timestamps builtin", function()
            local results = loader.loadAll(Jade, { { name = "timestamps" } })
            assert.is_true(results.timestamps.ok)
        end)
    end)

    describe("setup multi-return", function()
        it("propagates false, err from setup", function()
            local bad = {
                name = "bad-plugin",
                version = "0.0.1",
                setup = function()
                    return false, "nope"
                end,
            }
            local ok, err = plugin.use(bad, {})
            assert.is_false(ok)
            assert.is_truthy(tostring(err):match("nope"))
            assert.is_false(plugin.hasPlugin("bad-plugin"))
        end)
    end)

    describe("unregister (#171)", function()
        it("clears regular hooks under each type axis", function()
            local fired = 0
            Hooks.register("beforeQuery", function() fired = fired + 1 end, { plugin = "axis-unreg" })
            Hooks.register("afterCreate", function() fired = fired + 10 end, { plugin = "axis-unreg" })

            Hooks.unregister("axis-unreg")

            Hooks.fire("beforeQuery")
            Hooks.fire("afterCreate")
            assert.are.equal(0, fired, "regular hooks must not fire after unregister")
        end)

        it("keeps other plugins' regular hooks", function()
            local keep, drop = 0, 0
            Hooks.register("beforeQuery", function() keep = keep + 1 end, { plugin = "keep-me" })
            Hooks.register("beforeQuery", function() drop = drop + 1 end, { plugin = "drop-me" })

            Hooks.unregister("drop-me")
            Hooks.fire("beforeQuery")

            assert.are.equal(1, keep, "other plugin hooks must survive")
            assert.are.equal(0, drop, "unregistered plugin hooks must be gone")
        end)

        it("clears globalExtend* for the plugin", function()
            local extend_fired = false
            Hooks.register("extendEntity", function() extend_fired = true end, { plugin = "extend-unreg" })
            Hooks.unregister("extend-unreg")
            Hooks.fire("extendEntity")
            assert.is_false(extend_fired)
        end)
    end)

    describe("unloadPlugin removes behavior (#171)", function()
        it("use → unload → fire() finds nothing", function()
            local fired = 0
            plugin.use({
                name = "unload-hooks",
                version = "1.0.0",
                hooks = {
                    beforeQuery = function() fired = fired + 1 end,
                    extendEntity = function() fired = fired + 100 end,
                },
                setup = function() return true end,
            })

            -- Sanity: hooks are live after use()
            Hooks.fire("beforeQuery")
            assert.are.equal(1, fired, "hooks must fire while installed")

            local ok, err = plugin.unloadPlugin("unload-hooks")
            assert.is_true(ok)
            assert.is_nil(err)

            Hooks.fire("beforeQuery")
            Hooks.fire("extendEntity")
            assert.are.equal(1, fired, "hooks must not fire after unloadPlugin")
        end)
    end)

    describe("setup failure unregisters hooks (#171)", function()
        it("register hooks then setup returns false → hooks are cleared", function()
            local fired = 0
            local ok, err = plugin.use({
                name = "fail-setup-hooks",
                version = "1.0.0",
                hooks = {
                    beforeQuery = function() fired = fired + 1 end,
                },
                setup = function()
                    return false, "setup deliberately failed"
                end,
            })

            assert.is_false(ok)
            assert.is_truthy(tostring(err):match("setup deliberately failed"))

            Hooks.fire("beforeQuery")
            assert.are.equal(0, fired, "hooks must be unregistered when setup fails")
        end)

        it("register hooks then setup errors → hooks are cleared", function()
            local fired = 0
            local ok = plugin.use({
                name = "error-setup-hooks",
                version = "1.0.0",
                hooks = {
                    beforeQuery = function() fired = fired + 1 end,
                },
                setup = function()
                    error("setup threw")
                end,
            })

            assert.is_false(ok)

            Hooks.fire("beforeQuery")
            assert.are.equal(0, fired, "hooks must be unregistered when setup raises")
        end)
    end)

    describe("extendEntity", function()
        it("fires hooks when entity is created", function()
            local called = false
            plugin.use({
                name = "test-extend",
                version = "1.0.0",
                hooks = {
                    extendEntity = function(ctx)
                        called = true
                        ctx.entity.customPing = function() return "pong" end
                    end,
                },
                setup = function() return true end,
            }, {})

            local E = Jade.Entity("plugin_extend_users", {
                id = Jade.Integer():primaryKey(),
            })
            assert.is_true(called)
            assert.are.equal("pong", E:customPing())
        end)
    end)

    describe("timestamps plugin", function()
        it("fills created_at on create hook context", function()
            loader.loadAll(Jade, { { name = "timestamps" } })
            local data = {}
            Hooks.fireCRUD({ _table = "t" }, "create", "before", nil, data)
            assert.is_not_nil(data.created_at)
            assert.is_not_nil(data.updated_at)
        end)
    end)

    describe("external plugin", function()
        it("loads from filesystem path via loadfile", function()
            local path = "spec/plugin/_tmp_external_demo.lua"
            local f = io.open(path, "w")
            assert.is_not_nil(f)
            f:write([[
local M = {}
M.name = "external-demo"
M.version = "1.0.0"
function M.setup() return true end
return M
]])
            f:close()

            local mod, err = loader.find({ name = "external-demo", source = "external", path = path })
            os.remove(path)
            assert.is_not_nil(mod)
            assert.is_nil(err)
            assert.are.equal("external-demo", mod.name)
        end)
    end)
end)
