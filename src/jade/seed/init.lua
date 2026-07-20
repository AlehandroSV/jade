local M = {}

-- Seed registry
local seed_files = {}

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
    local loader, err = loadfile(seed_path)
    if not loader then
        error("Failed to load seed file: " .. tostring(err))
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
