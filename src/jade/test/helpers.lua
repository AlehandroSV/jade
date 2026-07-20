local M = {}
local Quoting = require("jade.util.quoting")

-- Test helper state
local test_state = {
    original_driver = nil,
    transaction_active = false,
}

-- Setup test database
-- jade.test.setup({ database = "test", truncate = true, seed = true })
function M.setup(Jade, opts)
    opts = opts or {}
    local driver = Jade.driver()

    if opts.truncate then
        M.truncateAll(driver, opts.tables)
    end

    if opts.seed and opts.seed_path then
        local Seed = require("jade.seed")
        Seed.execute(driver, opts.seed_path)
    end

    return true
end

-- Truncate all tables or specific tables
function M.truncateAll(driver, tables)
    if tables then
        for _, table_name in ipairs(tables) do
            driver:execute("TRUNCATE TABLE " .. Quoting.quoteIdentifier(table_name) .. " CASCADE")
        end
    else
        -- Get all tables and truncate
        local result = driver:execute(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND type = 'BASE TABLE'"
        )
        for _, row in ipairs(result) do
            driver:execute("TRUNCATE TABLE " .. Quoting.quoteIdentifier(row.table_name) .. " CASCADE")
        end
    end
    return true
end

-- Run function in a transaction with auto-rollback
-- jade.test.transaction(function() ... end)
function M.transaction(driver, fn)
    driver:beginTransaction()
    local ok, err = pcall(fn)
    driver:rollbackTransaction()
    if not ok then
        error(err)
    end
    return true
end

-- Simple factory pattern for test data
-- local user = jade.factory(User):create()
-- local admin = jade.factory(User):create({ role = "admin" })
function M.factory(entity, overrides)
    overrides = overrides or {}
    return {
        entity = entity,
        overrides = overrides,
        create = function(self, extra_overrides)
            local data = {}
            -- Generate default values based on column types
            for name, col in pairs(self.entity._columns) do
                if col._name ~= "id" and col._name ~= "created_at" and col._name ~= "updated_at" then
                    if col.type == "string" or col._type == "string" then
                        data[name] = "test_" .. name .. "_" .. tostring(math.random(100000))
                    elseif col.type == "integer" or col._type == "integer" then
                        data[name] = math.random(1, 1000000)
                    elseif col.type == "boolean" or col._type == "boolean" then
                        data[name] = true
                    elseif col.type == "text" or col._type == "text" then
                        data[name] = "Test content " .. tostring(math.random(100000))
                    else
                        data[name] = "test_value"
                    end
                end
            end
            -- Apply overrides
            for k, v in pairs(self.overrides) do
                data[k] = v
            end
            -- Apply extra overrides
            if extra_overrides then
                for k, v in pairs(extra_overrides) do
                    data[k] = v
                end
            end
            return self.entity:create(data)
        end,
    }
end

-- Create multiple instances
-- jade.factory(User):createList(5)
function M.factoryList(entity, count, overrides)
    local results = {}
    for i = 1, count do
        results[i] = M.factory(entity, overrides):create()
    end
    return results
end

return M
