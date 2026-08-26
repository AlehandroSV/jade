local M = {}

-- Encryption configuration (global — legacy / fallback)
local enc_config = {
    key = nil,
    algorithm = "aes",  -- "aes" for database-native, "custom" for user-provided functions
    database_encrypted = false,
    fields = {},
    -- Custom encryption functions (used when algorithm = "custom")
    encrypt_fn = nil,   -- function(value, key) -> encrypted_value
    decrypt_fn = nil,   -- function(encrypted_value, key) -> value
}

-- Per-entity encryption configuration
local entity_configs = {}

-- Column-level encryption markers
local encrypted_columns = {}

-- Warn once about global configure when per-entity configs exist
local _warned_global_over_entity = false

-- Validate and sanitize file path to prevent directory traversal and arbitrary file loading
local function validatePath(path, allowedExtension)
    if type(path) ~= "string" or path == "" then
        error("Invalid path: must be a non-empty string")
    end
    
    -- Reject paths with null bytes
    if path:find("\0") then
        error("Invalid path: contains null byte")
    end
    
    -- Reject directory traversal attempts
    if path:match("%.%.%/?") or path:match("/%.%.") then
        error("Invalid path: directory traversal not allowed")
    end
    
    -- Reject absolute paths outside current directory context
    -- Allow relative paths only
    if path:match("^/") or (path:match("^%a:") and not path:match("^%a:[\\/]")) then
        error("Invalid path: use relative paths only")
    end
    
    -- Validate extension
    if allowedExtension and not path:match("%." .. allowedExtension .. "$") then
        error("Invalid path: must have ." .. allowedExtension .. " extension")
    end
    
    return true
end

--- Set encryption config for a specific entity
--- @param entity_name string The entity/table name
--- @param opts table|nil Options: {key?, algorithm?, database_encrypted?, fields?, encrypt_fn?, decrypt_fn?}
function M.setEntityConfig(entity_name, opts)
    if not entity_name or type(entity_name) ~= "string" then
        error("setEntityConfig: entity_name must be a non-empty string")
    end

    if entity_configs[entity_name] and opts then
        -- Merge into existing entity config
        for k, v in pairs(opts) do
            entity_configs[entity_name][k] = v
        end
    else
        -- Create fresh entity-specific config
        entity_configs[entity_name] = setmetatable({}, {__index = enc_config})
        if opts then
            for k, v in pairs(opts) do
                entity_configs[entity_name][k] = v
            end
        end
    end
end

--- Get encryption config for a specific entity
--- Returns per-entity config if set, otherwise falls back to global config
--- @param entity_name string The entity/table name
--- @return table Config table (merged with globals as fallback)
function M.getEntityConfig(entity_name)
    return entity_configs[entity_name] or enc_config
end

--- Configure global encryption settings (legacy API)
--- Issues a warning if per-entity configs already exist
--- @param opts table Options: {key?, algorithm?, database_encrypted?, fields?, encrypt_fn?, decrypt_fn?, encrypt_file?, decrypt_file?}
function M.configure(opts)
    if next(entity_configs) and not only_entity then
        if not _warned_global_over_entity then
            _warned_global_over_entity = true
            print("[WARN] jade.Encryption.configure() called globally while per-entity configs exist. " ..
                  "Global keys will NOT affect entities that have their own .encryption() config.")
        end
    end

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
    validatePath(file_path, "lua")
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

-- Get global config (for backward compatibility)
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
    -- Per-entity markers
    if encrypted_columns[entity_name] and encrypted_columns[entity_name][column_name] then
        return true
    end

    -- Use per-entity config first, fallback to global
    local config = M.getEntityConfig(entity_name)

    if config.database_encrypted then
        return true
    end
    if config.fields[entity_name] then
        for _, field in ipairs(config.fields[entity_name]) do
            if field == column_name then return true end
        end
    end
    return false
end

-- Get fields that should be encrypted for an entity
function M.getEncryptedFields(entity_name, columns)
    local fields = {}
    local config = M.getEntityConfig(entity_name)

    -- From column-level markers
    if encrypted_columns[entity_name] then
        for col in pairs(encrypted_columns[entity_name]) do
            fields[col] = true
        end
    end

    -- From database-wide encryption (per-entity or global)
    if config.database_encrypted then
        for col_name in pairs(columns) do
            fields[col_name] = true
        end
    end

    -- From field-specific config (per-entity or global)
    if config.fields[entity_name] then
        for _, field in ipairs(config.fields[entity_name]) do
            fields[field] = true
        end
    end

    return fields
end

-- Get the encryption key for an entity
function M.getKey()
    return enc_config.key
end

function M.getEntityKey(entity_name)
    local config = M.getEntityConfig(entity_name)
    return config.key
end

-- Check if encryption is enabled (global)
function M.isEnabled()
    return enc_config.key ~= nil and enc_config.key ~= ""
end

function M.isEntityEnabled(entity_name)
    local config = M.getEntityConfig(entity_name)
    return config.key ~= nil and config.key ~= ""
end

-- Check if using custom encryption (Lua-level)
function M.isCustom()
    return enc_config.algorithm == "custom" and enc_config.encrypt_fn and enc_config.decrypt_fn
end

function M.isEntityCustom(entity_name)
    local config = M.getEntityConfig(entity_name)
    return config.algorithm == "custom" and config.encrypt_fn and config.decrypt_fn
end

-- Check if using database-native encryption
function M.isNative()
    return enc_config.algorithm == "aes" and M.isEnabled()
end

function M.isEntityNative(entity_name)
    local config = M.getEntityConfig(entity_name)
    return config.algorithm == "aes" and M.isEntityEnabled(entity_name)
end

--- Encrypt a value using custom function
--- @param value any The value to encrypt
--- @param entity_name string The entity/table name (optional for global)
--- @return any The encrypted value (or original if no custom function)
function M.encryptValue(value, entity_name)
    if value == nil then return nil end

    local config
    if entity_name then
        config = M.getEntityConfig(entity_name)
        if config.algorithm ~= "custom" or not config.encrypt_fn then
            return value
        end
        return config.encrypt_fn(value, config.key)
    else
        if not M.isCustom() then return value end
        return enc_config.encrypt_fn(value, enc_config.key)
    end
end

--- Decrypt a value using custom function
--- @param value any The value to decrypt
--- @param entity_name string The entity/table name (optional for global)
--- @return any The decrypted value (or original if no custom function)
function M.decryptValue(value, entity_name)
    if value == nil then return nil end

    local config
    if entity_name then
        config = M.getEntityConfig(entity_name)
        if config.algorithm ~= "custom" or not config.decrypt_fn then
            return value
        end
        return config.decrypt_fn(value, config.key)
    else
        if not M.isCustom() then return value end
        return enc_config.decrypt_fn(value, enc_config.key)
    end
end

--- Wrap a column reference with encryption function for INSERT/UPDATE
--- Only used for native (database-level) encryption
--- Uses session variables to avoid exposing the key in SQL strings
--- @param column_ref string The quoted column reference (e.g., '"email"')
--- @param driver table The database driver
--- @param entity_name string The entity/table name (optional for global)
--- @return string SQL fragment with encryption
function M.wrapEncrypt(column_ref, driver, entity_name)
    local config = entity_name and M.getEntityConfig(entity_name) or enc_config

    if not (config.key and config.key ~= "") or config.algorithm ~= "aes" then
        return column_ref
    end

    local driver_type = driver._driver_type or "postgresql"

    if driver_type == "postgresql" then
        -- Use session variable via current_setting() to avoid key exposure in SQL
        return string.format("pgp_sym_encrypt(%s::text, current_setting('jade.encryption_key'))", column_ref)
    elseif driver_type == "mysql" then
        -- Use session variable @jade_encryption_key to avoid key exposure in SQL
        return string.format("AES_ENCRYPT(%s, @jade_encryption_key)", column_ref)
    else
        error("Database encryption is not supported for " .. driver_type .. ". Use PostgreSQL with pgcrypto or MySQL.")
    end
end

--- Wrap a column reference with decryption function for SELECT
--- Only used for native (database-level) encryption
--- Uses session variables to avoid exposing the key in SQL strings
--- @param column_ref string The quoted column reference (e.g., '"email"')
--- @param driver table The database driver
--- @param entity_name string The entity/table name (optional for global)
--- @param as_name string Optional alias for the decrypted column
--- @return string SQL fragment with decryption
function M.wrapDecrypt(column_ref, driver, entity_name, as_name)
    local config = entity_name and M.getEntityConfig(entity_name) or enc_config

    if not (config.key and config.key ~= "") or config.algorithm ~= "aes" then
        return column_ref
    end

    local driver_type = driver._driver_type or "postgresql"
    local alias = as_name and (" AS " .. as_name) or ""

    if driver_type == "postgresql" then
        -- Use session variable via current_setting() to avoid key exposure in SQL
        return string.format("pgp_sym_decrypt(%s, current_setting('jade.encryption_key'))%s", column_ref, alias)
    elseif driver_type == "mysql" then
        -- Use session variable @jade_encryption_key to avoid key exposure in SQL
        return string.format("CAST(AES_DECRYPT(%s, @jade_encryption_key) AS CHAR)%s", column_ref, alias)
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
    local config = M.getEntityConfig(entity_name)
    if not (config.key and config.key ~= "") or config.algorithm ~= "aes" then
        return nil, nil  -- No native encryption, use default handling
    end

    if type(item) == "string" then
        if M.isEncrypted(entity_name, item) then
            local Quoting = require("jade.util.quoting")
            local col_ref = Quoting.quoteIdentifier(item)
            return M.wrapDecrypt(col_ref, driver, entity_name), {}
        end
    elseif type(item) == "table" and item._column then
        if M.isEncrypted(entity_name, item._column) then
            local Quoting = require("jade.util.quoting")
            local col_ref = Quoting.quoteIdentifier(item._column)
            local alias = item._alias and (" AS " .. Quoting.quoteIdentifier(item._alias)) or ""
            return M.wrapDecrypt(col_ref, driver, entity_name, nil) .. alias, {}
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
    local config = M.getEntityConfig(entity_name)

    if not (config.key and config.key ~= "") then
        return data, {}
    end

    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}
    local encrypt_cols = {}

    for k, v in pairs(data) do
        if fields[k] then
            if config.algorithm == "custom" and config.encrypt_fn then
                -- Custom encryption: encrypt in Lua
                result[k] = M.encryptValue(v, entity_name)
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
    local config = M.getEntityConfig(entity_name)

    if not (config.key and config.key ~= "") or config.algorithm ~= "custom" then
        return data  -- Native encryption handles decryption at SQL level
    end

    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}

    for k, v in pairs(data) do
        if fields[k] then
            result[k] = M.decryptValue(v, entity_name)
        else
            result[k] = v
        end
    end

    return result
end

-- Clear all encryption state (for testing)
function M.clear()
    enc_config = {
        key = nil,
        algorithm = "aes",
        database_encrypted = false,
        fields = {},
        encrypt_fn = nil,
        decrypt_fn = nil,
    }
    entity_configs = {}
    encrypted_columns = {}
    _warned_global_over_entity = false
end

return M
