local drivers = {}
local driver_modules = {}

local function register(name, module)
    drivers[name] = module
end

local function registerLazy(name, module_path)
    driver_modules[name] = module_path
end

local function get(name)
    -- Check if already loaded
    local driver = drivers[name]
    if driver then
        return driver
    end

    -- Check if lazy module exists
    local module_path = driver_modules[name]
    if module_path then
        driver = require(module_path)
        drivers[name] = driver
        return driver
    end

    error("Unknown driver: " .. tostring(name))
end

-- Register drivers lazily to avoid loading errors
registerLazy("postgresql", "jade.driver.postgresql")
registerLazy("mysql", "jade.driver.mysql")

return {
    register = register,
    get = get,
}
