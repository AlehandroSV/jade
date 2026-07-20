local Inflection = require("jade.util.inflection")
local Schema = require("jade.schema")
local Entity = require("jade.entity")

local Declarative = {}

-- Convention configuration
Declarative.conventions = {
    -- Table name: pluralize model name
    tableName = function(model_name)
        return Inflection.pluralize(model_name:lower())
    end,

    -- Primary key: id field with auto increment
    primaryKey = function()
        return { type = "integer", primary_key = true, auto_increment = true }
    end,

    -- Timestamps: created_at and updated_at
    timestamps = function()
        return {
            created_at = { type = "timestamp", default_now = true },
            updated_at = { type = "timestamp", default_now = true },
        }
    end,

    -- Foreign key: model_name_id
    foreignKey = function(model_name)
        return model_name:lower() .. "_id"
    end,

    -- Validations from constraints
    validations = function(constraints)
        local validations = {}
        if constraints.notNull then
            validations.presence = true
        end
        if constraints.unique then
            validations.uniqueness = true
        end
        return validations
    end,
}

-- Type mapping from simple names to column definitions
Declarative.typeMap = {
    string = { type = "string", length = 255 },
    text = { type = "text" },
    integer = { type = "integer" },
    bigint = { type = "bigint" },
    float = { type = "float" },
    decimal = { type = "decimal", precision = 10, scale = 2 },
    boolean = { type = "boolean" },
    timestamp = { type = "timestamp" },
    date = { type = "date" },
    uuid = { type = "uuid" },
    json = { type = "json" },
}

-- Parse a simple type string into a column definition
function Declarative.parseType(type_str)
    -- Check if it's a simple type name
    if Declarative.typeMap[type_str] then
        return Declarative.typeMap[type_str]
    end

    -- Check if it's a type with length: string(120)
    local type_name, length = type_str:match("^(%w+)%((%d+)%)$")
    if type_name and Declarative.typeMap[type_name] then
        local col = Declarative.typeMap[type_name]
        return { type = col.type, length = tonumber(length) }
    end

    -- Check if it's a decimal with precision: decimal(10,2)
    local dec_type, precision, scale = type_str:match("^(decimal)%((%d+),(%d+)%)$")
    if dec_type then
        return { type = "decimal", precision = tonumber(precision), scale = tonumber(scale) }
    end

    -- Default to string
    return { type = "string", length = 255 }
end

-- Parse a field definition
function Declarative.parseField(field_name, field_def)
    local column = {
        name = field_name,
        type = nil,
        length = nil,
        precision = nil,
        scale = nil,
        primary_key = false,
        unique = false,
        not_null = false,
        default = nil,
        default_now = false,
        references = nil,
        validations = {},
    }

    -- If field_def is a string, parse it as a type
    if type(field_def) == "string" then
        local parsed = Declarative.parseType(field_def)
        column.type = parsed.type
        column.length = parsed.length
        column.precision = parsed.precision
        column.scale = parsed.scale
        return column
    end

    -- If field_def is a table, use the definition directly
    if type(field_def) == "table" then
        column.type = field_def.type or "string"
        column.length = field_def.length
        column.precision = field_def.precision
        column.scale = field_def.scale
        column.primary_key = field_def.primary_key or false
        column.unique = field_def.unique or false
        column.not_null = field_def.not_null or field_def.notNull or false
        column.default = field_def.default
        column.default_now = field_def.default_now or field_def.defaultNow or false
        column.references = field_def.references
        return column
    end

    return column
end

-- Parse a model definition
function Declarative.parseModel(model_name, model_def)
    local model = {
        name = model_name,
        tableName = nil,
        fields = {},
        options = {},
        validations = {},
        relations = {},
    }

    -- Determine table name
    if model_def.table then
        model.tableName = model_def.table
    else
        model.tableName = Declarative.conventions.tableName(model_name)
    end

    -- Parse fields
    for field_name, field_def in pairs(model_def) do
        -- Skip special keys
        if field_name ~= "table" and field_name ~= "timestamps" and
           field_name ~= "softDeletes" and field_name ~= "validations" and
           field_name ~= "relations" then
            local field = Declarative.parseField(field_name, field_def)
            model.fields[field_name] = field
        end
    end

    -- Add timestamps if enabled
    if model_def.timestamps ~= false then
        local timestamps = Declarative.conventions.timestamps()
        for name, def in pairs(timestamps) do
            if not model.fields[name] then
                model.fields[name] = {
                    name = name,
                    type = def.type,
                    default_now = def.default_now,
                }
            end
        end
    end

    -- Add primary key if not defined
    local has_pk = false
    for _, field in pairs(model.fields) do
        if field.primary_key then
            has_pk = true
            break
        end
    end
    if not has_pk then
        local pk = Declarative.conventions.primaryKey()
        model.fields.id = {
            name = "id",
            type = pk.type,
            primary_key = pk.primary_key,
        }
    end

    -- Parse validations
    if model_def.validations then
        model.validations = model_def.validations
    end

    -- Parse relations
    if model_def.relations then
        model.relations = model_def.relations
    end

    -- Store options
    model.options.timestamps = model_def.timestamps ~= false
    model.options.softDeletes = model_def.softDeletes or false

    return model
end

-- Parse a complete schema definition
function Declarative.parse(schema_def)
    local schema = {
        models = {},
        options = schema_def.options or {},
    }

    for model_name, model_def in pairs(schema_def) do
        if model_name ~= "options" then
            schema.models[model_name] = Declarative.parseModel(model_name, model_def)
        end
    end

    return schema
end

-- Generate entity from parsed model
function Declarative.generateEntity(model)
    local columns = {}

    for field_name, field in pairs(model.fields) do
        local col_type = field.type

        -- Create column based on type
        local col = require("jade.schema.column").new(nil, col_type, field.length)
        col._name = field_name
        col._table = model.tableName

        if field.primary_key then
            col:primaryKey()
        end
        if field.unique then
            col:unique()
        end
        if field.not_null then
            col:notNull()
        end
        if field.default ~= nil then
            col:default(field.default)
        end
        if field.default_now then
            col:defaultNow()
        end
        if field.references then
            col:references(field.references.table, field.references.column)
        end

        columns[field_name] = col
    end

    -- Create entity
    local entity = Entity.new(model.tableName, columns)

    -- Add validations
    for field_name, validations in pairs(model.validations) do
        if columns[field_name] then
            for validation_type, options in pairs(validations) do
                if validation_type == "presence" and options == true then
                    entity:validatePresenceOf(field_name)
                elseif validation_type == "uniqueness" then
                    entity:validateUniquenessOf(field_name, type(options) == "table" and options or {})
                elseif validation_type == "length" then
                    entity:validateLengthOf(field_name, type(options) == "table" and options or {})
                elseif validation_type == "format" then
                    entity:validateFormatOf(field_name, type(options) == "table" and options or {})
                elseif validation_type == "inclusion" then
                    entity:validateInclusionOf(field_name, type(options) == "table" and options or {})
                elseif validation_type == "numericality" then
                    entity:validateNumericalityOf(field_name, type(options) == "table" and options or {})
                end
            end
        end
    end

    return entity
end

-- Generate migration from parsed schema
function Declarative.generateMigration(schema, migration_name)
    local migration = {
        name = migration_name or ("create_" .. table.concat(Declarative.getTableNames(schema), "_and_")),
        up = function(driver)
            for model_name, model in pairs(schema.models) do
                Declarative.createTableFromModel(driver, model)
            end
        end,
        down = function(driver)
            for model_name, model in pairs(schema.models) do
                Schema.dropTable(driver, model.tableName)
            end
        end,
    }

    return migration
end

-- Get table names from schema
function Declarative.getTableNames(schema)
    local names = {}
    for _, model in pairs(schema.models) do
        names[#names + 1] = model.tableName
    end
    return names
end

-- Create table from model definition
function Declarative.createTableFromModel(driver, model)
    local Table = require("jade.schema.table")
    local tbl = Table.new(model.tableName)

    -- Add columns
    for field_name, field in pairs(model.fields) do
        tbl:column(field_name, field.type, {
            length = field.length,
            precision = field.precision,
            scale = field.scale,
            primary_key = field.primary_key,
            unique = field.unique,
            null = not field.not_null,
            default = field.default,
            default_now = field.default_now,
        })
    end

    -- Add foreign keys from relations
    for _, relation in pairs(model.relations) do
        if relation.type == "belongsTo" then
            local fk_field = Declarative.conventions.foreignKey(relation.model)
            if not model.fields[fk_field] then
                tbl:column(fk_field, "integer", { null = true })
            end
            tbl:foreignKey({
                column = fk_field,
                references_table = Declarative.conventions.tableName(relation.model),
                references_column = "id",
                on_delete = relation.on_delete or "SET NULL",
            })
        end
    end

    -- Execute CREATE TABLE
    local sql = tbl:toSQL(driver)
    driver:execute(sql)

    -- Execute CREATE INDEX statements
    local index_statements = tbl:indexSQL()
    for _, idx_sql in ipairs(index_statements) do
        driver:execute(idx_sql)
    end

    return true
end

-- Create a schema definition helper function
function Declarative.define(schema_fn)
    local schema_def = {}
    local builder = {
        model = function(self, name, def)
            schema_def[name] = def
            return self
        end,
        options = function(self, opts)
            schema_def.options = opts
            return self
        end,
        build = function(self)
            return schema_def
        end,
    }

    setmetatable(builder, { __index = Declarative })
    schema_fn(builder)
    return Declarative.parse(schema_def)
end

-- Compare two schemas and generate diff
function Declarative.diff(old_schema, new_schema)
    local diff = {
        tables_to_create = {},
        tables_to_drop = {},
        tables_to_alter = {},
    }

    -- Find tables to create (in new but not in old)
    for model_name, model in pairs(new_schema.models) do
        if not old_schema.models[model_name] then
            diff.tables_to_create[#diff.tables_to_create + 1] = model
        end
    end

    -- Find tables to drop (in old but not in new)
    for model_name, model in pairs(old_schema.models) do
        if not new_schema.models[model_name] then
            diff.tables_to_drop[#diff.tables_to_drop + 1] = model
        end
    end

    -- Find tables to alter (in both but different)
    for model_name, new_model in pairs(new_schema.models) do
        local old_model = old_schema.models[model_name]
        if old_model then
            local changes = Declarative.diffModels(old_model, new_model)
            if changes then
                diff.tables_to_alter[#diff.tables_to_alter + 1] = {
                    model = new_model,
                    changes = changes,
                }
            end
        end
    end

    return diff
end

-- Compare two models and return changes
function Declarative.diffModels(old_model, new_model)
    local changes = {
        columns_to_add = {},
        columns_to_drop = {},
        columns_to_alter = {},
    }

    -- Find columns to add
    for field_name, field in pairs(new_model.fields) do
        if not old_model.fields[field_name] then
            changes.columns_to_add[#changes.columns_to_add + 1] = field
        end
    end

    -- Find columns to drop
    for field_name, field in pairs(old_model.fields) do
        if not new_model.fields[field_name] then
            changes.columns_to_drop[#changes.columns_to_drop + 1] = field
        end
    end

    -- Find columns to alter
    for field_name, new_field in pairs(new_model.fields) do
        local old_field = old_model.fields[field_name]
        if old_field then
            if Declarative.diffFields(old_field, new_field) then
                changes.columns_to_alter[#changes.columns_to_alter + 1] = {
                    old = old_field,
                    new = new_field,
                }
            end
        end
    end

    -- Check if there are any changes
    if #changes.columns_to_add == 0 and #changes.columns_to_drop == 0 and #changes.columns_to_alter == 0 then
        return nil
    end

    return changes
end

-- Compare two fields and return true if they are different
function Declarative.diffFields(old_field, new_field)
    return old_field.type ~= new_field.type or
           old_field.length ~= new_field.length or
           old_field.precision ~= new_field.precision or
           old_field.scale ~= new_field.scale or
           old_field.primary_key ~= new_field.primary_key or
           old_field.unique ~= new_field.unique or
           old_field.not_null ~= new_field.not_null or
           old_field.default ~= new_field.default or
           old_field.default_now ~= new_field.default_now or
           (old_field.references ~= new_field.references and
            (not old_field.references or not new_field.references or
             old_field.references.table ~= new_field.references.table or
             old_field.references.column ~= new_field.references.column))
end

-- Export schema to Lua format compatible with Esmeralda CLI
-- For single model: returns Jade.Entity(...)
-- For multiple models: returns table of entities
function Declarative.toLuaSchema(schema)
    local lines = {}
    local model_count = 0
    for _ in pairs(schema.models) do model_count = model_count + 1 end

    lines[#lines + 1] = 'local Jade = require("jade")'
    lines[#lines + 1] = ''

    if model_count == 1 then
        -- Single model: return entity directly
        for model_name, model in pairs(schema.models) do
            local entity_name = model.tableName
            lines[#lines + 1] = string.format('return Jade.Entity("%s", {', entity_name)

            for field_name, field in pairs(model.fields) do
                local col_def = Declarative.fieldToLua(field_name, field)
                lines[#lines + 1] = '    ' .. col_def .. ','
            end

            lines[#lines + 1] = '})'
        end
    else
        -- Multiple models: return table of entities
        lines[#lines + 1] = 'local entities = {}'
        lines[#lines + 1] = ''

        for model_name, model in pairs(schema.models) do
            local entity_name = model.tableName
            lines[#lines + 1] = string.format('entities["%s"] = Jade.Entity("%s", {', entity_name, entity_name)

            for field_name, field in pairs(model.fields) do
                local col_def = Declarative.fieldToLua(field_name, field)
                lines[#lines + 1] = '    ' .. col_def .. ','
            end

            lines[#lines + 1] = '})'
            lines[#lines + 1] = ''
        end

        lines[#lines + 1] = 'return entities'
    end

    return table.concat(lines, '\n')
end

-- Convert a field to Lua code
function Declarative.fieldToLua(field_name, field)
    local type_map = {
        string = "String",
        text = "Text",
        integer = "Integer",
        bigint = "Integer",
        float = "Float",
        decimal = "Decimal",
        boolean = "Boolean",
        timestamp = "Timestamp",
        date = "Date",
        uuid = "UUID",
        json = "JSON",
    }

    local lua_type = type_map[field.type] or "Text"
    local args = {}

    -- Add length for string types
    if field.length and (field.type == "string" or field.type == "varchar") then
        args[#args + 1] = tostring(field.length)
    end

    -- Add precision/scale for decimal
    if field.type == "decimal" then
        if field.precision and field.scale then
            args[#args + 1] = tostring(field.precision) .. "," .. tostring(field.scale)
        end
    end

    local arg_str = #args > 0 and "(" .. table.concat(args, ", ") .. ")" or "()"
    local col_def = string.format("%s = Jade.%s%s", field_name, lua_type, arg_str)

    -- Add modifiers
    local modifiers = {}

    if field.primary_key then
        modifiers[#modifiers + 1] = ":primaryKey()"
    end

    if field.not_null then
        modifiers[#modifiers + 1] = ":notNull()"
    end

    if field.unique then
        modifiers[#modifiers + 1] = ":unique()"
    end

    if field.default ~= nil then
        if type(field.default) == "string" then
            modifiers[#modifiers + 1] = string.format(':default("%s")', field.default)
        else
            modifiers[#modifiers + 1] = string.format(":default(%s)", tostring(field.default))
        end
    end

    if field.default_now then
        modifiers[#modifiers + 1] = ":defaultNow()"
    end

    if field.references then
        modifiers[#modifiers + 1] = string.format(':references("%s", "%s")', field.references.table, field.references.column)
    end

    if #modifiers > 0 then
        col_def = col_def .. table.concat(modifiers)
    end

    return col_def
end

-- Export schema to separate Lua files (Esmeralda format)
function Declarative.toLuaFiles(schema, output_dir)
    local files = {}

    for model_name, model in pairs(schema.models) do
        local filename = model.tableName .. ".lua"
        local content = Declarative.modelToLua(model)
        files[filename] = content
    end

    return files
end

-- Convert a single model to Lua file content
function Declarative.modelToLua(model)
    local lines = {}

    lines[#lines + 1] = 'local Jade = require("jade")'
    lines[#lines + 1] = ''
    lines[#lines + 1] = string.format('return Jade.Entity("%s", {', model.tableName)

    -- Add columns
    for field_name, field in pairs(model.fields) do
        local col_def = Declarative.fieldToLua(field_name, field)
        lines[#lines + 1] = '    ' .. col_def .. ','
    end

    lines[#lines + 1] = '})'

    return table.concat(lines, '\n')
end

-- Generate schema definition file for Esmeralda
function Declarative.generateSchemaFile(schema)
    local lines = {}

    lines[#lines + 1] = '-- Schema definition generated by Jade Declarative'
    lines[#lines + 1] = '-- Use with Esmeralda CLI: esmeralda generate'
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'local Jade = require("jade")'
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'local schema = {}'
    lines[#lines + 1] = ''

    for model_name, model in pairs(schema.models) do
        lines[#lines + 1] = string.format('schema["%s"] = {', model_name)

        -- Add table name if different from convention
        if model.tableName ~= Declarative.conventions.tableName(model_name) then
            lines[#lines + 1] = string.format('    table = "%s",', model.tableName)
        end

        -- Add fields
        for field_name, field in pairs(model.fields) do
            -- Skip auto-generated fields
            if field_name ~= "id" and field_name ~= "created_at" and field_name ~= "updated_at" then
                local field_def = Declarative.fieldToDeclarative(field_name, field)
                lines[#lines + 1] = '    ' .. field_def .. ','
            end
        end

        -- Add relations
        if next(model.relations) then
            lines[#lines + 1] = '    relations = {'
            for rel_name, relation in pairs(model.relations) do
                lines[#lines + 1] = string.format('        %s = { type = "%s", model = "%s" },', rel_name, relation.type, relation.model)
            end
            lines[#lines + 1] = '    },'
        end

        -- Add validations
        if next(model.validations) then
            lines[#lines + 1] = '    validations = {'
            for field_name, validations in pairs(model.validations) do
                lines[#lines + 1] = string.format('        %s = {', field_name)
                for val_type, options in pairs(validations) do
                    if type(options) == "table" then
                        lines[#lines + 1] = string.format('            %s = {', val_type)
                        for k, v in pairs(options) do
                            lines[#lines + 1] = string.format('                %s = %s,', k, tostring(v))
                        end
                        lines[#lines + 1] = '            },'
                    else
                        lines[#lines + 1] = string.format('            %s = %s,', val_type, tostring(options))
                    end
                end
                lines[#lines + 1] = '        },'
            end
            lines[#lines + 1] = '    },'
        end

        lines[#lines + 1] = '}'
        lines[#lines + 1] = ''
    end

    lines[#lines + 1] = 'return schema'

    return table.concat(lines, '\n')
end

-- Convert a field to declarative format
function Declarative.fieldToDeclarative(field_name, field)
    -- If it's a simple field with no special options, use string format
    if not field.primary_key and not field.unique and not field.not_null and
       not field.default and not field.default_now and not field.references and
       not field.precision and not field.scale then
        if field.length and field.length ~= 255 then
            return string.format('%s = "%s(%d)"', field_name, field.type, field.length)
        elseif field.type == "decimal" and field.precision and field.scale then
            return string.format('%s = "%s(%d,%d)"', field_name, field.type, field.precision, field.scale)
        else
            return string.format('%s = "%s"', field_name, field.type)
        end
    end

    -- Otherwise use table format
    local parts = {}
    parts[#parts + 1] = string.format('type = "%s"', field.type)

    if field.length then
        parts[#parts + 1] = string.format('length = %d', field.length)
    end

    if field.precision then
        parts[#parts + 1] = string.format('precision = %d', field.precision)
    end

    if field.scale then
        parts[#parts + 1] = string.format('scale = %d', field.scale)
    end

    if field.primary_key then
        parts[#parts + 1] = 'primary_key = true'
    end

    if field.unique then
        parts[#parts + 1] = 'unique = true'
    end

    if field.not_null then
        parts[#parts + 1] = 'not_null = true'
    end

    if field.default ~= nil then
        if type(field.default) == "string" then
            parts[#parts + 1] = string.format('default = "%s"', field.default)
        else
            parts[#parts + 1] = string.format('default = %s', tostring(field.default))
        end
    end

    if field.default_now then
        parts[#parts + 1] = 'default_now = true'
    end

    if field.references then
        parts[#parts + 1] = string.format('references = { table = "%s", column = "%s" }', field.references.table, field.references.column)
    end

    return string.format('%s = { %s }', field_name, table.concat(parts, ', '))
end

-- Prisma-like schema parser
-- Parses a simplified schema definition string into a parsed schema table
--
-- Syntax:
--   model User {
--     id    = Integer().primaryKey()
--     name  = String(120)
--     email = String(255)!
--     bio   = Text()?
--     role  = String(50)!default("user")
--     posts = hasMany(Post)
--   }
--
function Declarative.parsePrismaSchema(schema_str)
    local models = {}
    local current_model = nil

    for line in schema_str:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^%-%-") then
            -- Model start: model Name {
            local model_name = trimmed:match("^model%s+(%w+)%s*{?$")
            if model_name then
                current_model = {
                    name = model_name,
                    tableName = Declarative.conventions.tableName(model_name),
                    fields = {},
                    relations = {},
                    options = {},
                }
                models[model_name] = current_model
            -- Model end: }
            elseif trimmed == "}" then
                current_model = nil
            elseif current_model then
                -- Option: table = "custom_name"
                local option_key, option_val = trimmed:match("^(%w+)%s*=%s*(.+)$")
                if option_key == "table" then
                    current_model.tableName = option_val:match('^"(.*)"$') or option_val
                elseif option_key == "timestamps" then
                    current_model.options.timestamps = option_val == "true"
                elseif option_key == "id" then
                    if option_val == "false" then
                        current_model.options.noId = true
                    else
                        current_model.options.idType = option_val
                    end
                else
                    -- Field definition
                    local field_name, field_def = trimmed:match("^(%w+)%s*=%s*(.+)$")
                    if field_name and field_def then
                        local field = Declarative._parsePrismaField(field_name, field_def)
                        if field.relation then
                            current_model.relations[field_name] = field.relation
                        else
                            current_model.fields[field_name] = field
                        end
                    end
                end
            end
        end
    end

    -- Add convention fields
    for _, model in pairs(models) do
        if not model.options.noId then
            model.fields.id = Declarative.conventions.primaryKey()
        end
        if model.options.timestamps ~= false then
            for k, v in pairs(Declarative.conventions.timestamps()) do
                model.fields[k] = v
            end
        end
    end

    return models
end

-- Parse a single Prisma field definition
function Declarative._parsePrismaField(name, def)
    local result = { name = name }

    -- Check for modifiers
    local required = def:match("!") ~= nil
    local optional = def:match("%?") ~= nil
    local default_match = def:match("!default%((.+)%)$")

    -- Remove modifiers for type parsing
    local type_str = def:gsub("!", ""):gsub("%?", ""):gsub("!default%(.+%)$", ""):match("^%s*(.-)%s*$")

    -- Check for default value
    local default_val = nil
    if default_match then
        default_val = default_match:match('^"(.*)"$') or default_match
    end

    -- Check for relation: hasMany(Model), belongsTo(Model)
    local rel_type, rel_model = type_str:match("^(hasMany|hasOne|belongsTo)%((%w+)%)")
    if rel_type then
        result.relation = {
            type = rel_type,
            target = rel_model,
            foreign_key = Declarative.conventions.foreignKey(rel_model),
        }
        return result
    end

    -- Parse type: String(120), Integer, Text, etc.
    local col = Declarative.parseType(type_str)
    if col then
        if not col.length and not col.precision then
            -- Try to get length from type string
            local t, l = type_str:match("^(%w+)%((%d+)%)$")
            if t and l then col.length = tonumber(l) end
        end
        result.type = col.type
        if col.length then result.length = col.length end
        if col.precision then result.precision = col.precision end
        if col.scale then result.scale = col.scale end
    end

    -- Apply constraints
    if required then result.notNull = true end
    if optional then result.nullable = true end
    if default_val then result.default = default_val end

    return result
end

return Declarative
