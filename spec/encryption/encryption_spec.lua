describe("Encryption", function()
    local Encryption = require("jade.encryption")

    before_each(function()
        Encryption.clear()
    end)

    ----------------------------------------------------------------
    -- Configuration
    ----------------------------------------------------------------

    describe("configure", function()
        it("sets global encryption key", function()
            Encryption.clear()
            Encryption.configure({ key = "secret123" })
            local config = Encryption.getConfig()
            assert.are.equal("secret123", config.key)
        end)

        it("sets algorithm to aes by default", function()
            Encryption.clear()
            Encryption.configure({ key = "secret" })
            local config = Encryption.getConfig()
            assert.are.equal("aes", config.algorithm)
        end)

        it("sets custom algorithm with functions", function()
            Encryption.clear()
            local encrypt_fn = function(v, k) return v .. "_enc" end
            local decrypt_fn = function(v, k) return v:gsub("_enc$", "") end
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = encrypt_fn,
                decrypt_fn = decrypt_fn,
            })
            local config = Encryption.getConfig()
            assert.are.equal("custom", config.algorithm)
            assert.is_not_nil(config.encrypt_fn)
            assert.is_not_nil(config.decrypt_fn)
        end)

        it("sets database_encrypted flag", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", database_encrypted = true })
            local config = Encryption.getConfig()
            assert.is_true(config.database_encrypted)
        end)

        it("sets fields list", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                fields = { users = { "email", "password" } }
            })
            local config = Encryption.getConfig()
            assert.are.equal(2, #config.fields.users)
            assert.are.equal("email", config.fields.users[1])
        end)
    end)

    ----------------------------------------------------------------
    -- Per-entity configuration
    ----------------------------------------------------------------

    describe("setEntityConfig", function()
        it("sets config for specific entity", function()
            Encryption.clear()
            Encryption.setEntityConfig("users", { key = "user_secret" })
            local config = Encryption.getEntityConfig("users")
            assert.are.equal("user_secret", config.key)
        end)

        it("falls back to global config when entity not configured", function()
            Encryption.clear()
            Encryption.configure({ key = "global_secret" })
            local config = Encryption.getEntityConfig("users")
            assert.are.equal("global_secret", config.key)
        end)

        it("merges into existing entity config", function()
            Encryption.clear()
            Encryption.setEntityConfig("users", { key = "secret1" })
            Encryption.setEntityConfig("users", { algorithm = "custom" })
            local config = Encryption.getEntityConfig("users")
            assert.are.equal("secret1", config.key)
            assert.are.equal("custom", config.algorithm)
        end)

        it("errors on invalid entity_name", function()
            Encryption.clear()
            assert.has_error(function()
                Encryption.setEntityConfig(nil, {})
            end)
            assert.has_error(function()
                Encryption.setEntityConfig(123, {})
            end)
        end)
    end)

    ----------------------------------------------------------------
    -- Column marking
    ----------------------------------------------------------------

    describe("markColumn / isEncrypted", function()
        it("marks column as encrypted", function()
            Encryption.clear()
            Encryption.markColumn("users", "email")
            assert.is_true(Encryption.isEncrypted("users", "email"))
        end)

        it("returns false for unmarked column", function()
            Encryption.clear()
            assert.is_false(Encryption.isEncrypted("users", "name"))
        end)

        it("respects database_encrypted flag", function()
            Encryption.clear()
            Encryption.setEntityConfig("users", {
                key = "secret",
                database_encrypted = true,
            })
            assert.is_true(Encryption.isEncrypted("users", "any_column"))
        end)

        it("respects fields list", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                fields = { users = { "email" } }
            })
            assert.is_true(Encryption.isEncrypted("users", "email"))
            assert.is_false(Encryption.isEncrypted("users", "name"))
        end)
    end)

    ----------------------------------------------------------------
    -- Custom encryption functions
    ----------------------------------------------------------------

    describe("encryptValue / decryptValue", function()
        it("encrypts and decrypts with custom functions", function()
            Encryption.clear()
            local encrypt_fn = function(v, k) return v .. "_encrypted" end
            local decrypt_fn = function(v, k) return v:gsub("_encrypted$", "") end
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = encrypt_fn,
                decrypt_fn = decrypt_fn,
            })
            local encrypted = Encryption.encryptValue("hello")
            assert.are.equal("hello_encrypted", encrypted)
            local decrypted = Encryption.decryptValue(encrypted)
            assert.are.equal("hello", decrypted)
        end)

        it("returns nil for nil input", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = function(v) return v end,
                decrypt_fn = function(v) return v end,
            })
            assert.is_nil(Encryption.encryptValue(nil))
            assert.is_nil(Encryption.decryptValue(nil))
        end)

        it("returns original value when not custom algorithm", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local result = Encryption.encryptValue("hello")
            assert.are.equal("hello", result)
        end)

        it("uses entity-specific config when provided", function()
            Encryption.clear()
            Encryption.configure({
                key = "global",
                algorithm = "custom",
                encrypt_fn = function(v, k) return v .. "_global" end,
                decrypt_fn = function(v, k) return v end,
            })
            Encryption.setEntityConfig("users", {
                key = "entity",
                algorithm = "custom",
                encrypt_fn = function(v, k) return v .. "_entity" end,
                decrypt_fn = function(v, k) return v end,
            })
            local global_enc = Encryption.encryptValue("test")
            local entity_enc = Encryption.encryptValue("test", "users")
            assert.are.equal("test_global", global_enc)
            assert.are.equal("test_entity", entity_enc)
        end)
    end)

    ----------------------------------------------------------------
    -- Native encryption SQL wrapping
    ----------------------------------------------------------------

    describe("wrapEncrypt / wrapDecrypt", function()
        it("wraps column for PostgreSQL encryption", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local driver = { _driver_type = "postgresql" }
            local wrapped = Encryption.wrapEncrypt('"email"', driver)
            assert.is_true(wrapped:find("pgp_sym_encrypt") ~= nil)
            assert.is_true(wrapped:find("current_setting") ~= nil)
        end)

        it("wraps column for MySQL encryption", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local driver = { _driver_type = "mysql" }
            local wrapped = Encryption.wrapEncrypt("`email`", driver)
            assert.is_true(wrapped:find("AES_ENCRYPT") ~= nil)
            assert.is_true(wrapped:find("@jade_encryption_key") ~= nil)
        end)

        it("returns original when no key configured", function()
            Encryption.clear()
            local driver = { _driver_type = "postgresql" }
            local wrapped = Encryption.wrapEncrypt('"email"', driver)
            assert.are.equal('"email"', wrapped)
        end)

        it("wraps column for PostgreSQL decryption", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local driver = { _driver_type = "postgresql" }
            local wrapped = Encryption.wrapDecrypt('"email"', driver)
            assert.is_true(wrapped:find("pgp_sym_decrypt") ~= nil)
        end)

        it("wraps column for MySQL decryption", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local driver = { _driver_type = "mysql" }
            local wrapped = Encryption.wrapDecrypt("`email`", driver)
            assert.is_true(wrapped:find("AES_DECRYPT") ~= nil)
            assert.is_true(wrapped:find("CAST") ~= nil)
        end)

        it("errors for unsupported driver", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            local driver = { _driver_type = "sqlite" }
            assert.has_error(function()
                Encryption.wrapEncrypt('"email"', driver)
            end)
        end)
    end)

    ----------------------------------------------------------------
    -- Data preparation for INSERT/UPDATE
    ----------------------------------------------------------------

    describe("prepareInsert / prepareUpdate", function()
        it("encrypts fields with custom algorithm", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = function(v, k) return v .. "_enc" end,
                decrypt_fn = function(v, k) return v end,
                fields = { users = { "email" } }
            })
            local data = { name = "John", email = "john@example.com" }
            local columns = { name = true, email = true }
            local driver = {}
            local result, markers = Encryption.prepareInsert(data, "users", columns, driver)
            assert.are.equal("John", result.name)
            assert.are.equal("john@example.com_enc", result.email)
            assert.is_nil(markers.email)
        end)

        it("marks fields for native encryption", function()
            Encryption.clear()
            -- Ensure clean state
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "aes",
                fields = { users = { "email" } }
            })
            local data = { name = "John", email = "john@example.com" }
            local columns = { name = true, email = true }
            local driver = {}
            local result, markers = Encryption.prepareInsert(data, "users", columns, driver)
            -- For native encryption, values should remain unchanged
            assert.are.equal("John", result.name)
            assert.are.equal("john@example.com", result.email)
            -- But should be marked for SQL-level encryption
            assert.is_true(markers.email)
        end)

        it("returns original data when no key configured", function()
            Encryption.clear()
            local data = { name = "John", email = "john@example.com" }
            local columns = { name = true, email = true }
            local driver = {}
            local result, markers = Encryption.prepareInsert(data, "users", columns, driver)
            assert.are.equal(data, result)
            assert.are.equal(0, next(markers) and 1 or 0)
        end)
    end)

    ----------------------------------------------------------------
    -- Decryption after SELECT
    ----------------------------------------------------------------

    describe("decryptFields", function()
        it("decrypts fields with custom algorithm", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = function(v, k) return v end,
                decrypt_fn = function(v, k) return v:gsub("_enc$", "") end,
                fields = { users = { "email" } }
            })
            local data = { name = "John", email = "john@example.com_enc" }
            local columns = { name = true, email = true }
            local result = Encryption.decryptFields("users", data, columns)
            assert.are.equal("John", result.name)
            assert.are.equal("john@example.com", result.email)
        end)

        it("returns original data for native encryption", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "aes",
                fields = { users = { "email" } }
            })
            local data = { name = "John", email = "john@example.com" }
            local columns = { name = true, email = true }
            local result = Encryption.decryptFields("users", data, columns)
            assert.are.equal(data, result)
        end)
    end)

    ----------------------------------------------------------------
    -- State management
    ----------------------------------------------------------------

    describe("clear", function()
        it("clears all encryption state", function()
            Encryption.clear()
            Encryption.configure({ key = "secret" })
            Encryption.markColumn("users", "email")
            Encryption.setEntityConfig("posts", { key = "post_secret" })
            Encryption.clear()
            assert.is_nil(Encryption.getConfig().key)
            assert.is_false(Encryption.isEncrypted("users", "email"))
            assert.are.equal(Encryption.getConfig(), Encryption.getEntityConfig("posts"))
        end)
    end)

    ----------------------------------------------------------------
    -- Utility functions
    ----------------------------------------------------------------

    describe("isEnabled / isCustom / isNative", function()
        it("isEnabled returns true when key is set", function()
            Encryption.clear()
            Encryption.configure({ key = "secret" })
            assert.is_true(Encryption.isEnabled())
        end)

        it("isEnabled returns false when key is nil", function()
            Encryption.clear()
            assert.is_false(Encryption.isEnabled())
        end)

        it("isCustom returns true for custom algorithm with functions", function()
            Encryption.clear()
            Encryption.configure({
                key = "secret",
                algorithm = "custom",
                encrypt_fn = function() end,
                decrypt_fn = function() end,
            })
            assert.is_true(Encryption.isCustom())
        end)

        it("isNative returns true for aes algorithm with key", function()
            Encryption.clear()
            Encryption.configure({ key = "secret", algorithm = "aes" })
            assert.is_true(Encryption.isNative())
        end)
    end)

    ----------------------------------------------------------------
    -- validatePath (security)
    ----------------------------------------------------------------

    describe("validatePath (security)", function()
        it("accepts valid relative paths with .lua extension", function()
            assert.is_true(Encryption.validatePath("keys/encrypt.lua", "lua"))
            assert.is_true(Encryption.validatePath("crypto/keys.lua", "lua"))
            assert.is_true(Encryption.validatePath("./keys.lua", "lua"))
        end)

        it("rejects Unix directory traversal (../)", function()
            assert.has_error(function()
                Encryption.validatePath("../../etc/passwd", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("foo/../../etc", "lua")
            end)
        end)

        it("rejects Windows directory traversal (..\\)", function()
            assert.has_error(function()
                Encryption.validatePath("..\\..\\etc\\passwd", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("foo\\..\\..\\etc", "lua")
            end)
        end)

        it("rejects double dot in any context", function()
            assert.has_error(function()
                Encryption.validatePath("file..backup.lua", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("..hidden.lua", "lua")
            end)
        end)

        it("rejects null bytes in path", function()
            assert.has_error(function()
                Encryption.validatePath("keys\0.lua", "lua")
            end)
        end)

        it("rejects Unix absolute paths", function()
            assert.has_error(function()
                Encryption.validatePath("/etc/keys/encrypt.lua", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("/absolute/path.lua", "lua")
            end)
        end)

        it("rejects Windows absolute paths", function()
            assert.has_error(function()
                Encryption.validatePath("C:\\keys\\encrypt.lua", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("D:/keys.lua", "lua")
            end)
        end)

        it("rejects paths without required extension", function()
            assert.has_error(function()
                Encryption.validatePath("keys.txt", "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath("keys.lua.bak", "lua")
            end)
        end)

        it("rejects empty paths", function()
            assert.has_error(function()
                Encryption.validatePath("", "lua")
            end)
        end)

        it("rejects non-string paths", function()
            assert.has_error(function()
                Encryption.validatePath(123, "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath(nil, "lua")
            end)
            assert.has_error(function()
                Encryption.validatePath(true, "lua")
            end)
        end)

        it("uses generic error message to avoid leaking validation details", function()
            local ok, err = pcall(function()
                Encryption.validatePath("../../etc/passwd", "lua")
            end)
            assert.is_falsy(ok)
            assert.is_truthy(type(err) == "string")
            assert.is_truthy(err:find("rejected by security policy"))
            assert.is_falsy(err:find("null byte"))
            assert.is_falsy(err:find("traversal"))
        end)
    end)
end)
