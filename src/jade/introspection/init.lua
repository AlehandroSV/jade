local M = {}

-- Reader module
M.reader = require("jade.introspection.reader")

-- Converter module
M.converter = require("jade.introspection.converter")

-- Introspect database and generate schema
function M.introspect(driver, options)
    options = options or {}

    -- Read schema from database
    local schema = M.reader.readSchema(driver)

    -- Generate Jade schema code
    local schema_code = M.converter.generateSchema(schema)

    -- Generate migration if requested
    local migration_code = nil
    if options.generate_migration then
        local name = options.migration_name or "introspect_" .. os.date("%Y%m%d%H%M%S")
        migration_code = M.converter.generateMigration(schema, name)
    end

    return {
        schema = schema,
        schema_code = schema_code,
        migration_code = migration_code,
    }
end

-- Introspect and save to files
function M.introspectAndSave(driver, options)
    options = options or {}

    local result = M.introspect(driver, options)

    -- Save schema file
    local schema_path = options.schema_path or "schema/introspected.lua"
    local file = io.open(schema_path, "w")
    if file then
        file:write(result.schema_code)
        file:close()
    end

    -- Save migration file if generated
    if result.migration_code then
        local migration_path = options.migration_path
        if not migration_path then
            local timestamp = os.date("%Y%m%d%H%M%S")
            local name = options.migration_name or "introspect"
            migration_path = string.format("migrations/%s_%s.lua", timestamp, name)
        end

        local mig_file = io.open(migration_path, "w")
        if mig_file then
            mig_file:write(result.migration_code)
            mig_file:close()
        end
    end

    return result
end

return M
