--- Jade Plugin: Encryption
--- Wraps encryption/init.lua as a pluggable module.
---
--- Usage:
---   local Plugins = require("jade.plugin")
---   Plugins.use(require("jade.plugin.encryption"), { key = "my-key", algorithm = "aes" })
---
--- Supports per-entity config via options.fields table, and global fallback.
--- Database-native AES (PostgreSQL pgcrypto / MySQL AES_ENCRYPT) or custom Lua encrypt/decrypt functions.

local M = {}

M.name        = "encryption"
M.version     = "1.0.0"
M.description = "Field-level encryption with database-native or custom algorithms"

-- The encryption module doesn't use extendEntity — it uses markColumn() during
-- entity column definition. So we provide an init hook that marks encrypted columns
-- when entities are configured.
M.hooks = {}

--- Install encryption configuration.
--- @param jade table The plugin API instance
--- @param opts table|nil { key?, algorithm?, database_encrypted?, fields?, encrypt_fn?, decrypt_fn? }
--- @return boolean ok
function M.setup(jade, opts)
    if not opts then return true end

    -- Validate options
    if opts.key and type(opts.key) ~= "string" then
        return false, "encryption key must be a string"
    end

    if opts.algorithm and opts.algorithm ~= "aes" and opts.algorithm ~= "custom" then
        return false, "encryption algorithm must be 'aes' or 'custom'"
    end

    -- If using custom encryption, require both encrypt_fn and decrypt_fn
    if opts.algorithm == "custom" and (not opts.encrypt_fn or not opts.decrypt_fn) then
        return false, "custom encryption requires both encrypt_fn and decrypt_fn"
    end

    -- Set up the underlying encryption module
    local Encryption = require("jade.encryption")

    if opts.key then
        Encryption.configure({ key = opts.key })
    end

    if opts.algorithm then
        Encryption.configure({ algorithm = opts.algorithm })
    end

    if opts.database_encrypted ~= nil then
        Encryption.configure({ database_encrypted = opts.database_encrypted })
    end

    -- Per-field encryption from plugin options
    if opts.fields and type(opts.fields) == "table" then
        for _, field_ in ipairs(opts.fields) do
            if type(field_) == "string" then
                Encryption.markColumn("__all__", field_)  -- mark on all entities
            elseif type(field_) == "table" and field_.table and field_.field then
                Encryption.markColumn(field_.table, field_.field)
            end
        end
    end

    if opts.encrypt_fn then
        Encryption.configure({ encrypt_fn = opts.encrypt_fn })
    end

    if opts.decrypt_fn then
        Encryption.configure({ decrypt_fn = opts.decrypt_fn })
    end

    return true
end

function M.teardown(jade)
    -- No state to clean up.
end

return M
