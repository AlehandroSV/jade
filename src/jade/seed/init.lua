local M = {}
local errors = require("jade.errors")

-- Seed registry
local seed_files = {}

-- Validate and sanitize file path to prevent directory traversal and arbitrary file loading
-- Exported as M.validatePath for testability
function M.validatePath(path, allowedExtension)
    local function reject()
        errors.raise(errors.INVALID_INPUT, { details = "rejected by security policy" }, 3)
    end
    if type(path) ~= "string" or path == "" then
        reject()
    end

    -- Reject paths with null bytes
    if path:find("\0", 1, true) then
        reject()
    end

    -- Reject directory traversal attempts (.. in any context: ../, ..\, etc.)
    if path:find("..", 1, true) then
        reject()
    end

    -- Reject absolute paths: Unix /, Windows drive (C: or C:\), UNC \\
    if path:match("^/") or path:match("^%a:") or path:match("^\\\\") then
        reject()
    end

    -- Validate extension (allowedExtension must be alphanumeric)
    if allowedExtension and not path:match("%." .. allowedExtension .. "$") then
        reject()
    end

    return true
end

-- Local alias for internal call sites
local validatePath = M.validatePath

-- Register a seed file
function M.register(name, path)
    seed_files[name] = path
end

-- Get all registered seed files sorted by name
function M.getAll()
    local names = {}
    for name in pairs(seed_files) do
        names[#names + 1] = name
    end
    table.sort(names)
    local result = {}
    for _, name in ipairs(names) do
        result[#result + 1] = { name = name, path = seed_files[name] }
    end
    return result
end

-- Load and execute a seed file
function M.execute(driver, seed_path)
    validatePath(seed_path, "lua")
    local loader, err = loadfile(seed_path)
    if not loader then
        errors.raise(errors.CONFIG_INVALID, {
            details = "Failed to load seed file: " .. tostring(err),
        }, 2)
    end

    local seed_data = loader()

    -- Support both formats:
    -- 1. Simple: return { {table = "users", data = {...}} }
    -- 2. Factory: return { factories = {...}, data = {...} }

    if seed_data.factories then
        -- Apply defaults from factories
        for _, row in ipairs(seed_data.data or {}) do
            local factory = seed_data.factories[row._factory]
            if factory then
                -- Merge defaults with row data
                local merged = {}
                for k, v in pairs(factory.defaults or {}) do
                    merged[k] = v
                end
                for k, v in pairs(row) do
                    if k ~= "_factory" then
                        merged[k] = v
                    end
                end
                -- Apply faker functions for missing values
                for k, v in pairs(factory.faker or {}) do
                    if merged[k] == nil then
                        merged[k] = v()
                    end
                end
                -- Execute insert
                if merged.table then
                    local table_name = merged.table
                    merged.table = nil
                    local sql, bindings = driver:generateInsert(table_name, merged)
                    driver:execute(sql, bindings)
                end
            end
        end
    elseif seed_data.table then
        -- Simple format: single table
        local sql, bindings = driver:generateInsert(seed_data.table, seed_data.data[1] or {})
        for i = 2, #seed_data.data do
            local sql2, bindings2 = driver:generateInsert(seed_data.table, seed_data.data[i])
            driver:execute(sql2, bindings2)
        end
        driver:execute(sql, bindings)
    else
        -- Array format: { {table = "users", data = {...}}, ... }
        for _, entry in ipairs(seed_data) do
            if entry.table and entry.data then
                for _, row in ipairs(entry.data) do
                    local sql, bindings = driver:generateInsert(entry.table, row)
                    driver:execute(sql, bindings)
                end
            end
        end
    end

    return true
end

-- Clear seed registry
function M.clear()
    seed_files = {}
end

return M
