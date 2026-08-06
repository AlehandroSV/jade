describe("Cache", function()
    local cache

    before_each(function()
        cache = require("jade.cache")
        cache._reset()
        cache.configure({ driver = "memory", max_size = 3 })
    end)

    describe("MemoryStore", function()
        it("stores and retrieves values", function()
            cache.set("key1", "value1")
            assert.are.equal("value1", cache.get("key1"))
        end)

        it("returns nil for missing keys", function()
            assert.is_nil(cache.get("missing"))
        end)

        it("respects TTL expiration", function()
            cache.set("key1", "value1", 0)
            -- TTL of 0 means already expired on next get
            assert.is_nil(cache.get("key1"))
        end)

        it("deletes entries", function()
            cache.set("key1", "value1")
            cache.delete("key1")
            assert.is_nil(cache.get("key1"))
        end)

        it("clears all entries", function()
            cache.set("key1", "value1")
            cache.set("key2", "value2")
            cache.clear()
            assert.is_nil(cache.get("key1"))
            assert.is_nil(cache.get("key2"))
        end)
    end)

    describe("LRU eviction", function()
        it("evicts least recently used entry when cache is full", function()
            cache.set("a", "value_a") -- oldest access
            cache.set("b", "value_b") -- middle access
            cache.set("c", "value_c") -- newest access

            -- Access "a" and "b" to update their accessed_at
            cache.get("a")
            cache.get("b")

            -- Adding "d" should evict "c" (least recently accessed)
            cache.set("d", "value_d")

            assert.is_nil(cache.get("c"))
            assert.are.equal("value_a", cache.get("a"))
            assert.are.equal("value_b", cache.get("b"))
            assert.are.equal("value_d", cache.get("d"))
        end)

        it("evicts oldest entry when none are accessed via get", function()
            cache.set("first", "value_1")
            cache.set("second", "value_2")
            cache.set("third", "value_3")

            -- Without any get() calls, "first" has the oldest accessed_at
            cache.set("fourth", "value_4")

            assert.is_nil(cache.get("first"))
            assert.are.equal("value_2", cache.get("second"))
            assert.are.equal("value_3", cache.get("third"))
            assert.are.equal("value_4", cache.get("fourth"))
        end)

        it("updates accessed_at on get", function()
            cache.set("a", "value_a")
            cache.set("b", "value_b")
            cache.set("c", "value_c")

            -- Access "a" to make it most recently used
            cache.get("a")

            -- Adding "d" should evict "b" (now least recently used)
            cache.set("d", "value_d")

            assert.are.equal("value_a", cache.get("a"))
            assert.is_nil(cache.get("b"))
            assert.are.equal("value_c", cache.get("c"))
            assert.are.equal("value_d", cache.get("d"))
        end)

        it("does not evict when updating existing key", function()
            cache.set("a", "value_a")
            cache.set("b", "value_b")
            cache.set("c", "value_c")

            -- Updating existing key should not trigger eviction
            cache.set("a", "new_value_a")

            assert.are.equal("new_value_a", cache.get("a"))
            assert.are.equal("value_b", cache.get("b"))
            assert.are.equal("value_c", cache.get("c"))
        end)

        it("evicts correctly with the issue example scenario", function()
            -- Scenario from issue #60:
            -- max_size = 2
            cache.configure({ max_size = 2 })
            cache._reset()
            cache.configure({ driver = "memory", max_size = 2 })

            -- Entry A: added first (oldest accessed_at)
            cache.set("a", "value_a", 300)

            -- Entry B: added second (newer accessed_at)
            cache.set("b", "value_b", 60)

            -- New entry C needs to be added
            -- Bug: would evict B (lower TTL), but should evict A (older)
            cache.set("c", "value_c")

            assert.is_nil(cache.get("a"))
            assert.are.equal("value_b", cache.get("b"))
            assert.are.equal("value_c", cache.get("c"))
        end)
    end)

    describe("keygen", function()
        it("generates cache keys with prefix and parts", function()
            local key = cache.keygen("user", { 1, "profile" })
            assert.are.equal("user:1:profile", key)
        end)
    end)

    describe("invalidatePattern", function()
        it("invalidates keys matching prefix pattern", function()
            cache.set("user:1:name", "Alice")
            cache.set("user:2:name", "Bob")
            cache.set("post:1:title", "Hello")

            local count = cache.invalidatePattern("user:*")
            assert.are.equal(2, count)
            assert.is_nil(cache.get("user:1:name"))
            assert.is_nil(cache.get("user:2:name"))
            assert.are.equal("Hello", cache.get("post:1:title"))
        end)
    end)
end)
