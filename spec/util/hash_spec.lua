describe("util.hash", function()
    local HASH_PATH = "src/jade/util/hash.lua"

    local function read_source()
        local f = io.open(HASH_PATH, "r")
        if not f then
            error("cannot open " .. HASH_PATH, 2)
        end
        local src = f:read("*a")
        f:close()
        return src
    end

    describe("Lua 5.1/5.2 parse compatibility (#170)", function()
        it("source contains no binary or unary ~ operator", function()
            local src = read_source()
            -- Strip ~= (comparison) then any remaining ~ is bitwise and breaks 5.1/5.2
            local stripped = src:gsub("~=", "")
            assert.are.equal(nil, stripped:find("~", 1, true))
        end)

        it("loads jade.util.hash without parse errors", function()
            local ok, mod = pcall(require, "jade.util.hash")
            assert.is_true(ok)
            assert.are.equal("table", type(mod))
        end)
    end)

    describe("_weakHash", function()
        local Hash = require("jade.util.hash")

        it("returns 8 hex chars", function()
            local h = Hash._weakHash("hello")
            assert.are.equal(8, #h)
            assert.is_truthy(h:match("^[0-9a-f]+$"))
        end)

        it("is deterministic", function()
            assert.are.equal(Hash._weakHash("abc"), Hash._weakHash("abc"))
        end)

        it("differs for different inputs", function()
            assert.is_false(Hash._weakHash("abc") == Hash._weakHash("abd"))
        end)

        it("matches known FNV-1a 32-bit values", function()
            -- FNV-1a 32-bit: empty -> 0x811c9dc5
            assert.are.equal("811c9dc5", Hash._weakHash(""))
            -- FNV-1a 32-bit of "a" -> 0xe40c292c
            assert.are.equal("e40c292c", Hash._weakHash("a"))
        end)
    end)

    describe("constantTimeCompare", function()
        local Hash = require("jade.util.hash")

        it("returns true for equal strings", function()
            assert.is_true(Hash.constantTimeCompare("abcdef", "abcdef"))
            assert.is_true(Hash.constantTimeCompare("", ""))
        end)

        it("returns false for different content", function()
            assert.is_false(Hash.constantTimeCompare("abcdef", "abcdeg"))
            assert.is_false(Hash.constantTimeCompare("abc", "abd"))
        end)

        it("returns false for different lengths", function()
            assert.is_false(Hash.constantTimeCompare("abc", "abcd"))
            assert.is_false(Hash.constantTimeCompare("", "a"))
        end)
    end)

    describe("hmacSha256 / audit integrity", function()
        local Hash = require("jade.util.hash")

        it("hmacSha256 returns hex string", function()
            local h = Hash.hmacSha256("data", "secret")
            assert.are.equal("string", type(h))
            assert.is_truthy(h:match("^[0-9a-f]+$"))
            assert.is_true(#h >= 8)
        end)

        it("hmacSha256 is deterministic for same inputs", function()
            assert.are.equal(
                Hash.hmacSha256("payload", "key"),
                Hash.hmacSha256("payload", "key")
            )
        end)

        it("hmacSha256 differs for different secrets", function()
            assert.is_false(
                Hash.hmacSha256("payload", "key1") == Hash.hmacSha256("payload", "key2")
            )
        end)

        it("hashAuditEntry + verifyAuditEntry roundtrip", function()
            local secret = "test-secret"
            local entry = {
                table_name = "users",
                record_id = "42",
                action = "update",
                changes = "name",
                created_at = "2026-01-01T00:00:00Z",
            }
            entry._integrity_hash = Hash.hashAuditEntry(entry, secret)
            assert.is_not_nil(entry._integrity_hash)
            assert.is_true(Hash.verifyAuditEntry(entry, secret))
            assert.is_false(Hash.verifyAuditEntry(entry, "wrong-secret"))
        end)

        it("verifyAuditEntry rejects missing hash", function()
            local entry = { table_name = "users", record_id = "1", action = "create" }
            assert.is_false(Hash.verifyAuditEntry(entry, "secret"))
        end)

        it("isCryptoAvailable returns boolean", function()
            local v = Hash.isCryptoAvailable()
            assert.are.equal("boolean", type(v))
        end)
    end)
end)
