local M = {}

-- WARNING: XOR+base64 is obfuscation, NOT encryption.
-- For production use requiring real security, integrate with a cryptographic library.
-- This module is provided for basic data masking and convenience only.

-- Encryption config
local enc_config = {
    key = nil,
    algorithm = "xor",
    database_encrypted = false,
    fields = {},
}

-- Column-level encryption markers
local encrypted_columns = {}

-- Configure encryption
function M.configure(opts)
    if opts.key then enc_config.key = opts.key end
    if opts.algorithm then enc_config.algorithm = opts.algorithm end
    if opts.database_encrypted ~= nil then enc_config.database_encrypted = opts.database_encrypted end
    if opts.fields then enc_config.fields = opts.fields end
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

-- XOR-based encrypt/decrypt (simple, no external deps)
-- Lua 5.1 compatible XOR for bytes using arithmetic
local function xorByte(a, b)
    local result = 0
    local power = 1
    for _ = 1, 8 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then
            result = result + power
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        power = power * 2
    end
    return result
end

local function xorCrypt(data, key)
    if not key or key == "" then return data end
    local result = {}
    local keyLen = #key
    for i = 1, #data do
        local dataByte = string.byte(data, i)
        local keyByte = string.byte(key, (i - 1) % keyLen + 1)
        result[i] = string.char(xorByte(dataByte, keyByte))
    end
    return table.concat(result)
end

-- Base64 encode
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64Encode(data)
    local result = {}
    local i = 1
    while i <= #data do
        local a, b, c = string.byte(data, i, i + 2)
        local padding = 3 - (#data - i + 1)
        if padding > 0 then c = 0 end
        if padding > 1 then b = 0 end
        local n = a * 65536 + b * 256 + c
        result[#result + 1] = string.sub(b64chars, math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = string.sub(b64chars, math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        if padding < 2 then
            result[#result + 1] = string.sub(b64chars, math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        else
            result[#result + 1] = "="
        end
        if padding < 1 then
            result[#result + 1] = string.sub(b64chars, n % 64 + 1, n % 64 + 1)
        else
            result[#result + 1] = "="
        end
        i = i + 3
    end
    return table.concat(result)
end

-- Base64 decode
local b64lookup = {}
for i = 1, 64 do b64lookup[string.byte(b64chars, i)] = i - 1 end
local function base64Decode(data)
    data = data:gsub("%s+", ""):gsub("=", "")
    local result = {}
    for i = 1, #data, 4 do
        local a = b64lookup[string.byte(data, i)] or 0
        local b = b64lookup[string.byte(data, i + 1)] or 0
        local c = b64lookup[string.byte(data, i + 2)] or 0
        local d = b64lookup[string.byte(data, i + 3)] or 0
        local n = a * 262144 + b * 4096 + c * 64 + d
        result[#result + 1] = string.char(math.floor(n / 65536) % 256)
        if i + 2 <= #data then
            result[#result + 1] = string.char(math.floor(n / 256) % 256)
        end
        if i + 3 <= #data then
            result[#result + 1] = string.char(n % 256)
        end
    end
    return table.concat(result)
end

-- Encrypt a value
function M.encrypt(value, key)
    if value == nil then return nil end
    if type(value) ~= "string" then value = tostring(value) end
    key = key or enc_config.key
    if not key then return value end
    local encrypted = xorCrypt(value, key)
    return "ENC:" .. base64Encode(encrypted)
end

-- Decrypt a value
function M.decrypt(value, key)
    if value == nil then return nil end
    if type(value) ~= "string" then return value end
    if value:sub(1, 4) ~= "ENC:" then return value end
    key = key or enc_config.key
    if not key then return value:sub(5) end
    local encoded = value:sub(5)
    local encrypted = base64Decode(encoded)
    return xorCrypt(encrypted, key)
end

-- Check if a value is encrypted
function M.isEncryptedValue(value)
    if type(value) ~= "string" then return false end
    return value:sub(1, 4) == "ENC:"
end

-- Encrypt data fields based on entity config
function M.encryptFields(entity_name, data, columns)
    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}
    for k, v in pairs(data) do
        if fields[k] and not M.isEncryptedValue(v) then
            result[k] = M.encrypt(v)
        else
            result[k] = v
        end
    end
    return result
end

-- Decrypt data fields based on entity config
function M.decryptFields(entity_name, data, columns)
    local fields = M.getEncryptedFields(entity_name, columns)
    local result = {}
    for k, v in pairs(data) do
        if fields[k] and M.isEncryptedValue(v) then
            result[k] = M.decrypt(v)
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
        algorithm = "xor",
        database_encrypted = false,
        fields = {},
    }
    encrypted_columns = {}
end

return M
