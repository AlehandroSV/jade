describe("Retry", function()
    local Retry = require("jade.util.retry")

    describe("calculateDelay", function()
        it("calculates exponential backoff", function()
            local config = { delay = 1000, backoff = "exponential", max_delay = 30000 }
            assert.are.equal(1000, Retry.calculateDelay(1, config))
            assert.are.equal(2000, Retry.calculateDelay(2, config))
            assert.are.equal(4000, Retry.calculateDelay(3, config))
            assert.are.equal(8000, Retry.calculateDelay(4, config))
        end)

        it("calculates linear backoff", function()
            local config = { delay = 1000, backoff = "linear", max_delay = 30000 }
            assert.are.equal(1000, Retry.calculateDelay(1, config))
            assert.are.equal(2000, Retry.calculateDelay(2, config))
            assert.are.equal(3000, Retry.calculateDelay(3, config))
            assert.are.equal(4000, Retry.calculateDelay(4, config))
        end)

        it("respects max_delay", function()
            local config = { delay = 1000, backoff = "exponential", max_delay = 5000 }
            assert.are.equal(1000, Retry.calculateDelay(1, config))
            assert.are.equal(2000, Retry.calculateDelay(2, config))
            assert.are.equal(4000, Retry.calculateDelay(3, config))
            assert.are.equal(5000, Retry.calculateDelay(4, config))  -- capped at max_delay
            assert.are.equal(5000, Retry.calculateDelay(5, config))  -- capped at max_delay
        end)

        it("uses default values", function()
            local config = {}
            local delay = Retry.calculateDelay(1, config)
            assert.is_true(delay > 0)
        end)
    end)

    describe("getConfig", function()
        it("returns retry config from driver config", function()
            local driver_config = {
                retry = {
                    max_attempts = 3,
                    delay = 2000,
                    backoff = "linear",
                    max_delay = 10000,
                }
            }
            local config = Retry.getConfig(driver_config)
            assert.are.equal(3, config.max_attempts)
            assert.are.equal(2000, config.delay)
            assert.are.equal("linear", config.backoff)
            assert.are.equal(10000, config.max_delay)
        end)

        it("returns default when no retry config", function()
            local config = Retry.getConfig({})
            assert.are.equal(1, config.max_attempts)
        end)

        it("returns default when nil config", function()
            local config = Retry.getConfig(nil)
            assert.are.equal(1, config.max_attempts)
        end)
    end)

    describe("execute", function()
        it("returns result on first success", function()
            local call_count = 0
            local function fn()
                call_count = call_count + 1
                return "success"
            end

            local result = Retry.execute(fn, { max_attempts = 3 }, "test")
            assert.are.equal("success", result)
            assert.are.equal(1, call_count)
        end)

        it("retries on failure and succeeds", function()
            local call_count = 0
            local function fn()
                call_count = call_count + 1
                if call_count < 3 then
                    error("fail")
                end
                return "success"
            end

            local result = Retry.execute(fn, { max_attempts = 3, delay = 1 }, "test")
            assert.are.equal("success", result)
            assert.are.equal(3, call_count)
        end)

        it("fails after max attempts", function()
            local call_count = 0
            local function fn()
                call_count = call_count + 1
                error("always fail")
            end

            assert.has_error(function()
                Retry.execute(fn, { max_attempts = 3, delay = 1 }, "test")
            end)
            assert.are.equal(3, call_count)
        end)

        it("works with max_attempts = 1 (no retry)", function()
            local call_count = 0
            local function fn()
                call_count = call_count + 1
                error("fail")
            end

            assert.has_error(function()
                Retry.execute(fn, { max_attempts = 1 }, "test")
            end)
            assert.are.equal(1, call_count)
        end)
    end)
end)
