-- Tests for structured logging (#97)

describe("Structured Logging", function()
    local log = require("jade.util.log")
    local captured = {}

    before_each(function()
        -- Clear captured table
        for k in pairs(captured) do captured[k] = nil end
        log.configure({
            enabled = true,
            level = "debug",
            format = "json",
            output = function(entry)
                captured[#captured + 1] = entry
            end,
        })
    end)

    it("accepts configuration", function()
        log.configure({ enabled = true, level = "info" })
        assert.is_true(true)
    end)

    it("respects log level", function()
        log.configure({
            enabled = true,
            level = "warn",
            output = function(entry)
                captured[#captured + 1] = entry
            end,
        })
        log.info("should not appear")
        assert.are.equal(0, #captured)
        log.warn("should appear")
        assert.are.equal(1, #captured)
    end)

    it("logs query with duration", function()
        log.query("SELECT * FROM users", {}, 50)
        assert.are.equal(1, #captured)
        assert.are.equal("query", captured[1].type)
        assert.are.equal(50, captured[1].duration_ms)
    end)

    it("logs slow query warning", function()
        log.configure({
            enabled = true,
            level = "debug",
            slow_query_threshold = 100,
            output = function(entry)
                captured[#captured + 1] = entry
            end,
        })
        log.query("SELECT * FROM users", {}, 250)
        assert.are.equal(2, #captured)
        assert.are.equal("slow_query", captured[2].type)
    end)

    it("does not log bindings when disabled", function()
        log.configure({
            enabled = true,
            level = "debug",
            log_bindings = false,
            output = function(entry)
                captured[#captured + 1] = entry
            end,
        })
        log.query("SELECT * FROM users WHERE id = ?", { 42 }, 10)
        assert.is_nil(captured[1].bindings)
    end)

    it("logs bindings when enabled", function()
        log.configure({
            enabled = true,
            level = "debug",
            log_bindings = true,
            output = function(entry)
                captured[#captured + 1] = entry
            end,
        })
        log.query("SELECT * FROM users WHERE id = ?", { 42 }, 10)
        assert.is_truthy(captured[1].bindings)
        assert.are.equal("42", captured[1].bindings)
    end)

    it("logs pool acquire", function()
        log.pool_acquire(10, 7)
        assert.are.equal(1, #captured)
        assert.are.equal("pool.acquire", captured[1].type)
    end)

    it("logs pool release", function()
        log.pool_release(10, 8)
        assert.are.equal(1, #captured)
        assert.are.equal("pool.release", captured[1].type)
    end)

    it("logs cache hit", function()
        log.cache_hit("users:active:true")
        assert.are.equal(1, #captured)
        assert.are.equal("cache.hit", captured[1].type)
    end)

    it("logs cache miss", function()
        log.cache_miss("users:active:true")
        assert.are.equal(1, #captured)
        assert.are.equal("cache.miss", captured[1].type)
    end)

    it("logs migration run", function()
        log.migration_run("create_users", 45)
        assert.are.equal(1, #captured)
        assert.are.equal("migration.run", captured[1].type)
    end)
end)
