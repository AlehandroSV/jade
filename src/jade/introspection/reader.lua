local M = {}

-- Read database schema from PostgreSQL
function M.readSchema(driver)
    local schema = {
        tables = {},
    }

    -- Get all tables
    local tables = driver:execute([[
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        ORDER BY table_name
    ]])

    for _, row in ipairs(tables) do
        local table_name = row.table_name
        local columns = M.readColumns(driver, table_name)
        local indexes = M.readIndexes(driver, table_name)
        local foreign_keys = M.readForeignKeys(driver, table_name)

        schema.tables[table_name] = {
            name = table_name,
            columns = columns,
            indexes = indexes,
            foreign_keys = foreign_keys,
        }
    end

    return schema
end

-- Read columns for a table
function M.readColumns(driver, table_name)
    local columns = {}

    local rows = driver:execute(string.format([[
        SELECT
            column_name,
            data_type,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            is_nullable,
            column_default
        FROM information_schema.columns
        WHERE table_name = '%s'
        AND table_schema = 'public'
        ORDER BY ordinal_position
    ]], table_name))

    for _, row in ipairs(rows) do
        local col = {
            name = row.column_name,
            type = M.mapColumnType(row.data_type),
            nullable = row.is_nullable == "YES",
            default = row.column_default,
        }

        if row.character_maximum_length then
            col.length = row.character_maximum_length
        end

        if row.numeric_precision then
            col.precision = row.numeric_precision
        end

        if row.numeric_scale then
            col.scale = row.numeric_scale
        end

        -- Detect primary key
        if row.column_default and row.column_default:match("nextval") then
            col.primary_key = true
            col.auto_increment = true
        end

        columns[row.column_name] = col
    end

    return columns
end

-- Read indexes for a table
function M.readIndexes(driver, table_name)
    local indexes = {}

    local rows = driver:execute(string.format([[
        SELECT
            indexname,
            indexdef
        FROM pg_indexes
        WHERE tablename = '%s'
        AND schemaname = 'public'
    ]], table_name))

    for _, row in ipairs(rows) do
        -- Skip primary key indexes (they're handled by column definition)
        if not row.indexname:match("_pkey$") then
            indexes[row.indexname] = {
                name = row.indexname,
                definition = row.indexdef,
                unique = row.indexdef:match("UNIQUE") ~= nil,
            }
        end
    end

    return indexes
end

-- Read foreign keys for a table
function M.readForeignKeys(driver, table_name)
    local foreign_keys = {}

    local rows = driver:execute(string.format([]
        SELECT
            tc.constraint_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_name = '%s'
        AND tc.table_schema = 'public'
    ]], table_name))

    for _, row in ipairs(rows) do
        foreign_keys[row.constraint_name] = {
            name = row.constraint_name,
            column = row.column_name,
            foreign_table = row.foreign_table_name,
            foreign_column = row.foreign_column_name,
        }
    end

    return foreign_keys
end

-- Map PostgreSQL column types to Jade types
function M.mapColumnType(pg_type)
    local type_map = {
        ["character varying"] = "string",
        ["varchar"] = "string",
        ["text"] = "text",
        ["integer"] = "integer",
        ["bigint"] = "integer",
        ["smallint"] = "integer",
        ["serial"] = "integer",
        ["bigserial"] = "integer",
        ["numeric"] = "decimal",
        ["decimal"] = "decimal",
        ["real"] = "float",
        ["double precision"] = "float",
        ["boolean"] = "boolean",
        ["timestamp with time zone"] = "timestamp",
        ["timestamp without time zone"] = "timestamp",
        ["timestamp"] = "timestamp",
        ["date"] = "date",
        ["uuid"] = "uuid",
        ["json"] = "json",
        ["jsonb"] = "json",
    }

    return type_map[pg_type] or "text"
end

return M
