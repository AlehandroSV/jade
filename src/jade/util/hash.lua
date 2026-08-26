--- Cryptographic Hash Utility for Jade ORM
--- Provides HMAC-SHA256 hashing for audit log integrity verification
--- @module jade.util.hash

local M = {}

-- Try to load LuaCrypto or FFI-based implementation
local crypto_ok, crypto = pcall(require, "crypto")

-- FFI setup for OpenSSL if crypto module not available
local ffi_ok, ffi = pcall(require, "ffi")
local openssl_loaded = false

if ffi_ok and not crypto_ok then
    local load_ok = pcall(function()
        ffi.cdef[[
            typedef struct evp_md_ctx_st EVP_MD_CTX;
            typedef struct engine_st ENGINE;

            const EVP_MD *EVP_sha256(void);
            EVP_MD_CTX *EVP_MD_CTX_new(void);
            void EVP_MD_CTX_free(EVP_MD_CTX *ctx);
            int EVP_DigestInit_ex(EVP_MD_CTX *ctx, const EVP_MD *type, ENGINE *impl);
            int EVP_DigestUpdate(EVP_MD_CTX *ctx, const void *d, size_t cnt);
            int EVP_DigestFinal_ex(EVP_MD_CTX *ctx, unsigned char *md, unsigned int *s);
            
            unsigned char *HMAC(const EVP_MD *evp_md, const void *key, int key_len,
                                const unsigned char *data, size_t data_len,
                                unsigned char *md, unsigned int *md_len);
        ]]
        
        local C = ffi.load("ssl")
        openssl_loaded = true
    end)
end

-- Generate HMAC-SHA256 hash of data with secret key
--- @param data string Data to hash
--- @param secret string Secret key for HMAC
--- @return string hex Hexadecimal representation of the hash
function M.hmacSha256(data, secret)
    if crypto_ok and crypto.hmac then
        -- LuaCrypto implementation
        local hmac_hex = crypto.hmac("sha256", secret, data)
        return hmac_hex:gsub(".", function(c) 
            return string.format("%02x", string.byte(c)) 
        end)
    elseif openssl_loaded then
        -- FFI/OpenSSL implementation
        local C = ffi.load("ssl")
        local md_len = ffi.new("unsigned int[1]")
        local result = C.HMAC(C.EVP_sha256(), secret, #secret, data, #data, nil, md_len)
        
        local hex = {}
        for i = 0, md_len[0] - 1 do
            hex[#hex + 1] = string.format("%02x", result[i])
        end
        return table.concat(hex)
    else
        -- Fallback: simple SHA256-like hash (not cryptographically secure!)
        -- Warning: This is only for environments without crypto libraries
        warn("No crypto library available. Using weak hash for audit integrity.")
        return M._weakHash(data .. secret)
    end
end

-- Weak hash fallback (NOT cryptographically secure - use only when no crypto available)
function M._weakHash(data)
    local hash = 0x811c9dc5
    for i = 1, #data do
        local byte = data:byte(i)
        hash = bit32 and bit32.bxor(hash, byte) or (hash ~ byte)
        hash = bit32 and bit32.mul(hash, 0x01000193) or (hash * 0x01000193) % 0x100000000
    end
    return string.format("%08x", hash)
end

-- Generate a hash for an audit log entry to ensure integrity
--- @param entry table Audit log entry
--- @param secret string Secret key (should be stored securely, not in code)
--- @return string hex Hash of the entry
function M.hashAuditEntry(entry, secret)
    -- Serialize entry deterministically
    local parts = {
        tostring(entry.table_name or ""),
        tostring(entry.record_id or ""),
        tostring(entry.action or ""),
        tostring(entry.changes or ""),
        tostring(entry.created_at or ""),
    }
    local data = table.concat(parts, "|")
    return M.hmacSha256(data, secret)
end

-- Verify audit log entry integrity
--- @param entry table Audit log entry (must include _integrity_hash field)
--- @param secret string Secret key used to generate the hash
--- @return boolean true if hash matches, false otherwise
function M.verifyAuditEntry(entry, secret)
    if not entry._integrity_hash then
        return false
    end
    
    local expected_hash = entry._integrity_hash
    local computed_hash = M.hashAuditEntry(entry, secret)
    
    -- Constant-time comparison to prevent timing attacks
    return M.constantTimeCompare(expected_hash, computed_hash)
end

-- Constant-time string comparison to prevent timing attacks
--- @param a string First string
--- @param b string Second string
--- @return boolean true if equal, false otherwise
function M.constantTimeCompare(a, b)
    if #a ~= #b then
        return false
    end
    
    local result = 0
    for i = 1, #a do
        result = bit32 and bit32.bor(result, bit32.bxor(a:byte(i), b:byte(i))) 
                 or ((a:byte(i) ~ b:byte(i)) ~= 0 and 1 or 0)
    end
    
    return result == 0
end

-- Check if cryptographic functions are available
--- @return boolean
function M.isCryptoAvailable()
    return crypto_ok or openssl_loaded
end

return M
