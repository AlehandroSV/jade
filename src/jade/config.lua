local M = {}

local config = nil

-- Default environment variable fallbacks (order matters)
local DEFAULT_ENV_FALLBACKS = {
    "JADE_ENV",
    "RAILS_ENV",     -- Ruby on Rails
    "NODE_ENV",      -- Node.js / Express
    "GO_ENV",        -- Go
    "APP_ENV",       -- Elixir / Phoenix
    "FLASK_ENV",     -- Python / Flask
    "RACK_ENV",      -- Ruby (genérico)
}

-- Validate and sanitize file path to prevent directory traversal
-- Exported as M.validatePath for testability
function M.validatePath(path, allowedExtension)
    if type(path) ~= "string" or path == "" then
        error("Invalid path: rejected by security policy")
    end

    -- Reject paths with null bytes
    if path:find("\0", 1, true) then
        error("Invalid path: rejected by security policy")
    end

    -- Reject directory traversal attempts (.. in any context: ../, ..\, etc.)
    if path:find("..", 1, true) then
        error("Invalid path: rejected by security policy")
    end

    -- Reject absolute paths (Unix / or Windows drive letter with separator)
    if path:match("^/") or path:match("^%a:[\\/]") then
        error("Invalid path: rejected by security policy")
    end

    -- Validate extension (allowedExtension must be alphanumeric)
    if allowedExtension and not path:match("%." .. allowedExtension .. "$") then
        error("Invalid path: rejected by security policy")
    end

    return true
end

-- Environment detection with extensible fallbacks
local function detectEnvironment()
    local fallbacks = DEFAULT_ENV_FALLBACKS
    if config and config.env_vars then
        fallbacks = config.env_vars
    end
    for _, var in ipairs(fallbacks) do
        local value = os.getenv(var)
        if value and value ~= "" then
            return value
        end
    end
    return "development"
end

-- Resolve environment variable references in config values
local function resolveEnvVars(obj)
    if type(obj) == "string" then
        -- Match ${VAR_NAME} or ${VAR_NAME:default}
        local resolved = obj:gsub("%$%{([^}:]+):?([^}]*)%}", function(var, default)
            return os.getenv(var) or default
        end)
        return resolved
    elseif type(obj) == "table" then
        local result = {}
        for k, v in pairs(obj) do
            result[k] = resolveEnvVars(v)
        end
        return result
    end
    return obj
end

-- Deep merge two tables (b overrides a)
local function deepMerge(a, b)
    local result = {}
    for k, v in pairs(a) do
        if type(v) == "table" and type(b[k]) == "table" then
            result[k] = deepMerge(v, b[k])
        else
            result[k] = v
        end
    end
    for k, v in pairs(b) do
        if result[k] == nil or type(v) ~= "table" then
            result[k] = v
        elseif type(result[k]) == "table" then
            result[k] = deepMerge(result[k], v)
        end
    end
    return result
end

function M.load(path)
    local config_path = path or "jade.config.lua"
    M.validatePath(config_path, "lua")
    local loader, err = loadfile(config_path)
    if not loader then
        error("Failed to load config: " .. tostring(err))
    end
    config = loader()
    return config
end

-- Load environment-specific configuration
-- Priority: jade.config.{JADE_ENV}.lua > jade.config.lua > defaults
function M.loadForEnvironment(basePath)
    local env = detectEnvironment()
    local base_dir = basePath or "."

    -- Validate basePath for traversal (basePath is developer-provided, so absolute is allowed)
    if base_dir:find("..", 1, true) or base_dir:find("\0", 1, true) then
        error("Invalid basePath: rejected by security policy")
    end

    -- Load base config
    local base_config = {}
    local base_file = base_dir .. "/jade.config.lua"
    local ok, result = pcall(function()
        -- Validate constructed path against traversal (env may be attacker-controlled)
        if base_file:find("..", 1, true) or base_file:find("\0", 1, true) then
            error("Invalid path: rejected by security policy")
        end
        local loader, err = loadfile(base_file)
        if not loader then error(err) end
        return loader()
    end)
    if ok then
        base_config = result
    end

    -- Load environment-specific config and merge
    local env_file = base_dir .. "/jade.config." .. env .. ".lua"
    local env_ok, env_result = pcall(function()
        if env_file:find("..", 1, true) or env_file:find("\0", 1, true) then
            error("Invalid path: rejected by security policy")
        end
        local loader, err = loadfile(env_file)
        if not loader then error(err) end
        return loader()
    end)
    if env_ok and env_result then
        config = deepMerge(base_config, env_result)
    else
        config = base_config
    end

    -- Resolve environment variables
    config = resolveEnvVars(config)

    return config
end

-- Parse a database URL string
-- Supports: postgresql://user:pass@host:port/db
--           mysql://user:pass@host:port/db
--           sqlite:///path/to/db
function M.parseURL(url)
    if type(url) ~= "string" then
        error("URL must be a string")
    end

    -- Extract scheme
    local scheme, rest = url:match("^(%w+)://(.+)$")
    if not scheme then
        error("Invalid URL format: " .. url)
    end

    -- Handle SQLite specially (no host/port)
    if scheme == "sqlite" then
        local db_path = rest
        -- sqlite:///path -> path
        if db_path:sub(1, 1) == "/" then
            db_path = db_path:sub(2)
        end
        return {
            driver = "sqlite",
            database = db_path,
        }
    end

    -- Parse user:pass@host:port/db
    local userinfo, hostpart = rest:match("^([^@]+)@(.+)$")
    local user, password
    if userinfo then
        user, password = userinfo:match("^([^:]+):?(.*)$")
        if password == "" then password = nil end
    else
        hostpart = rest
    end

    -- Parse host:port/db
    local host, port_str, database
    local slash_pos = hostpart:find("/")
    if slash_pos then
        database = hostpart:sub(slash_pos + 1)
        local hostport = hostpart:sub(1, slash_pos - 1)
        local colon_pos = hostport:find(":")
        if colon_pos then
            host = hostport:sub(1, colon_pos - 1)
            port_str = hostport:sub(colon_pos + 1)
        else
            host = hostport
        end
    else
        local colon_pos = hostpart:find(":")
        if colon_pos then
            host = hostpart:sub(1, colon_pos - 1)
            port_str = hostpart:sub(colon_pos + 1)
        else
            host = hostpart
        end
    end

    local port = port_str and tonumber(port_str) or nil
    local driver = scheme

    -- Normalize driver name
    if driver == "postgresql" or driver == "postgres" then
        driver = "postgresql"
        port = port or 5432
    elseif driver == "mysql" then
        port = port or 3306
    end

    return {
        driver = driver,
        host = host,
        port = port,
        database = database,
        user = user,
        password = password,
    }
end

function M.get()
    if not config then
        error("Jade not configured. Call jade.configure() first.")
    end
    return config
end

function M.set(new_config)
    config = new_config
end

-- Get current environment name
function M.getEnvironment()
    return detectEnvironment()
end

return M
