local M = {}

-- Encryption configuration
local enc_config = {
    key = nil,
    algorithm = "aes",  -- "aes" for database-native, "custom" for user-provided functions
    database_encrypted = false,
    fields = {},
    -- Custom encryption functions (used when algorithm = "custom")
    encrypt_fn = nil,   -- function(value, key) -> encrypted_value
    decrypt_fn = nil,   -- function(encrypted_value, key) -> value
}

-- Column-level encryption markers
local encrypted_columns = {}

-- Configure encryption
function M.configure(opts)
    if opts.key then enc_config.key = opts.key end
    if opts.algorithm then enc_config.algorithm = opts.algorithm end
    if opts.database_encrypted ~= nil then enc_config.database_encrypted = opts.database_encrypted end
    if opts.fields then enc_config.fields = opts.fields end

    -- Load encrypt/decrypt functions from files if provided
    if opts.encrypt_file then
        local fn = M.loadEncryptionFile(opts.encrypt_file)
        enc_config.encrypt_fn = fn
    elseif opts.encrypt_fn then
        enc_config.encrypt_fn = opts.encrypt_fn
    end

    if opts.decrypt_file then
        local fn = M.loadEncryptionFile(opts.decrypt_file)
        enc_config.decrypt_fn = fn
    elseif opts.decrypt_fn then
        enc_config.decrypt_fn = opts.decrypt_fn
    end
end

--- Load an encryption function from a Lua file
--- The file must return a function: function(value, key) -> transformed_value
--- @param file_path string Path to the Lua file
--- @return function The loaded function
function M.loadEncryptionFile(file_path)
    local loader, err = loadfile(file_path)
    if not loader then
        error("Failed to load encryption file '" .. file_path .. "': " .. tostring(err))
    end
    local fn = loader()
    if type(fn) ~= "function" then
        error("Encryption file '" .. file_path .. "' must return a function, got " .. type(fn))
    end
    return fn
end

-- Get config
function M.getConfig()
    return enc_config
end

-- Mark a column as encrypted
function M.markColumn(entity_name, column_name)
    if not encrypted_columns[entity_name] then
        encrypted_columns[entity_name] = {}
    end
    encrypted_columns[entity_name][column_name] = true
end

-- Check if a column should be encrypted
function M.isEncrypted(entity_name, column_name)
    if encrypted_columns[entity_name] and encrypted_columns[entity_name][column_name] then
        return true
    end
    if enc_config.database_encrypted then
        return true
    end
    if enc_config.fields[entity_name] then
        for _, field in ipairs(enc_config.fields[entity_name]) do
            if field == column_name then return true end
        end
    end
    return false
end

-- Get fields that should be encrypted for an entity
function M.getEncryptedFields(entity_name, columns)
    local fields = {}

    -- From column-level markers
    if encrypted_columns[entity_name] then
        for col in pairs(encrypted_columns[entity_name]) do
            fields[col] = true
        end
    end

    -- From database-wide encryption
    if enc_config.database_encrypted then
        for col_name in pairs(columns) do
            fields[col_name] = true
        end
    end

    -- From field-specific config
    if enc_config.fields[entity_name] then
        for _, field in ipairs(enc_config.fields[entity_name]) do
            fields[field] = true
        end
    end

    return fields
end

-- Get the encryption key
function M.getKey()
    return enc_config.key
end

-- Check if encryption is enabled
function M.isEnabled()
    return enc_config.key ~= nil and enc_config.key ~= ""
end

-- Check if using custom encryption (Lua-level)
function M.isCustom()
    return enc_config.algorithm == "custom" and enc_config.encrypt_fn and enc_config.decrypt_fn
end

-- Check if using database-native encryption
function M.isNative()
    return enc_config.algorithm == "aes" and M.isEnabled()
end

--- Encrypt a value using custom function
--- @param value any The value to encrypt
--- @return any The encrypted value (or original if no custom function)
function M.encryptValue(value)
    if value == nil then return nil end
    if not M.isCustom() then return value end
    return enc_config.encrypt_fn(value, enc_config.key)
end

--- Decrypt a value using custom function
--- @param value any The value to decrypt
--- @return any The decrypted value (or original if no custom function)
function M.decryptValue(value)
    if value == nil then return nil end
    if not M.isCustom() then return value end
    return enc_config.decrypt_fn(value, enc_config.key)
end

--- Wrap a column reference with encryption function for INSERT/UPDATE
--- Only used for native (database-level) encryption
--- @param column_ref string The quoted column reference (e.g., '"email"')
--- @param driver table The database driver
--- @return string SQL fragment with encryption
function M.wrapEncrypt(column_ref, driver)
    if not M.isEnabled() or M.isCustom() then
        return column_ref
    end

    local key = enc_config.key
    local driver_type = driver._driver_type or "postgresql"

    if driver_type == "postgresql" then
        return string.format("pgp_sym_encrypt(%s::text, '%s')", column_ref, key:gsub("'", "''"))
    elseif driver_type == "mysql" then
        return string.format("AES_ENCRYPT(%s, '%s')", column_ref, key:gsub("'", "''"))
    else
        error("Database encryption is not supported for " .. driver_type .. ". Use PostgreSQL with pgcrypto or MySQL.")
    end
end

--- Wrap a column reference with decryption function for SELECT
--- Only used for native (database-level) encryption
--- @param column_ref string The quoted column reference (e.g., '"email"')
--- @param driver table The database driver
--- @param as_name string Optional alias for the decrypted column
--- @return string SQL fragment with decryption
function M.wrapDecrypt(column_ref, driver, as_name)
    if not M.isEnabled() or M.isCustom() then
        return column_ref
    end

    local key = enc_config.key
    local driver_type = driver._driver_type or "postgresql"
    local alias = as_name and (" AS " .. as_name) or ""

    if driver_type == "postgresql" then
        return string.format("pgp_sym_decrypt(%s, '%s')%s", column_ref, key:gsub("'", "''"), alias)
    elseif driver_type == "mysql" then
        return string.format("CAST(AES_DECRYPT(%s, '%s') AS CHAR)%s", column_ref, key:gsub("'", "''"), alias)
    else
        error("Database decryption is not supported for " .. driver_type .. ". Use PostgreSQL with pgcrypto or MySQL.")
    end
end

--- Check if a SELECT item needs decryption wrapping
--- @param item string|table The select item
--- @param entity_name string The entity/table name
--- @param columns table The entity columns
--- @param driver table The database driver
--- @return string, table The resolved SQL fragment and any bindings
function M.resolveSelectItem(item, entity_name, columns, driver)
    if not M.isEnabled() or M.isCustom() then
        return nil, nil  -- No native encryption, use default handling
    end

    if type(item) == "string" then
        if M.isEncrypted(entity_name, item) then
            local Quoting = require("jade.util.quoting")
            local col_ref = Quoting.quoteIdentifier(item)
            return M.wrapDecrypt(col_ref, driver, Quoting.quoteIdentifier(item)), {}
        end
    elseif type(item) == "table" and item._column then
        if M.isEncrypted(entity_name, item._column) then
            local Quoting = require("jade.util.quoting")
            local col_ref = Quoting.quoteIdentifier(item._column)
            local alias = item._alias and (" AS " .. Quoting.quoteIdentifier(item._alias)) or ""
            return M.wrapDecrypt(col_ref, driver, nil) .. alias, {}
        end
    end

    return nil, nil
end

--- Prepare data for INSERT
--- For native encryption: marks columns for SQL-level encryption
--- For custom encryption: encrypts values in Lua before passing to driver
--- @param data table The input data
--- @param entity_name string The entity/table name
--- @param columns table The entity columns
--- @param driver table The database driver
--- @return table, table Modified data and encryption markers
function M.prepareInsert(data, entity_name, columns, driver)
    if not M.isEnabled() then
        return data, {}
    end

    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}
    local encrypt_cols = {}

    for k, v in pairs(data) do
        if fields[k] then
            if M.isCustom() then
                -- Custom encryption: encrypt in Lua
                result[k] = M.encryptValue(v)
            else
                -- Native encryption: mark for SQL-level encryption
                encrypt_cols[k] = true
                result[k] = v
            end
        else
            result[k] = v
        end
    end

    return result, encrypt_cols
end

--- Prepare data for UPDATE
--- For custom encryption: encrypts values in Lua before passing to driver
--- @param data table The input data
--- @param entity_name string The entity/table name
--- @param columns table The entity columns
--- @param driver table The database driver
--- @return table, table Modified data and encryption markers
function M.prepareUpdate(data, entity_name, columns, driver)
    return M.prepareInsert(data, entity_name, columns, driver)
end

--- Decrypt data fields after SELECT (only for custom encryption)
--- For native encryption, decryption is handled at SQL level by the driver
--- @param entity_name string The entity/table name
--- @param data table The row data from database
--- @param columns table The entity columns
--- @return table The decrypted row data
function M.decryptFields(entity_name, data, columns)
    if not M.isEnabled() or not M.isCustom() then
        return data  -- Native encryption handles decryption at SQL level
    end

    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}

    for k, v in pairs(data) do
        if fields[k] then
            result[k] = M.decryptValue(v)
        else
            result[k] = v
        end
    end

    return result
end

-- Clear config (for testing)
function M.clear()
    enc_config = {
        key = nil,
        algorithm = "aes",
        database_encrypted = false,
        fields = {},
        encrypt_fn = nil,
        decrypt_fn = nil,
        encrypt_file = nil,
        decrypt_file = nil,
    }
    encrypted_columns = {}
end

return M
