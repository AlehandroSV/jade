local Quoting = require("jade.util.quoting")

local Table = {}
Table.__index = Table

function Table.new(name)
    return setmetatable({
        name = name,
        columns = {},
        indexes = {},
        foreign_keys = {},
        options = {},
    }, Table)
end

function Table:column(name, type_name, options)
    options = options or {}
    local Column = require("jade.schema.column")
    local col = Column.new(nil, type_name, options.length, options.precision, options.scale)
    col._name = name
    col._table = self.name

    if options.primary_key then col:primaryKey() end
    if options.auto_increment then col:autoIncrement() end
    if options.unique then col:unique() end
    if options.null == false then col:notNull() end
    if options.default ~= nil then col:default(options.default) end
    if options.default_now then col:defaultNow() end
    if options.references then
        col:references(options.references.table, options.references.column)
    end

    self.columns[#self.columns + 1] = col
    return self
end

function Table:primaryKey(name)
    name = name or "id"
    return self:column(name, "integer", { primary_key = true, auto_increment = true })
end

function Table:timestamps()
    self:column("created_at", "timestamp", { default_now = true })
    self:column("updated_at", "timestamp", { default_now = true })
    return self
end

function Table:softDeletes(column)
    column = column or "deleted_at"
    self:column(column, "timestamp")
    return self
end

function Table:index(columns, options)
    options = options or {}
    if type(columns) == "string" then
        columns = { columns }
    end
    self.indexes[#self.indexes + 1] = {
        columns = columns,
        unique = options.unique or false,
        name = options.name,
    }
    return self
end

function Table:foreignKey(options)
    self.foreign_keys[#self.foreign_keys + 1] = {
        column = options.column,
        references_table = options.references_table,
        references_column = options.references_column or "id",
        on_delete = options.on_delete,
        on_update = options.on_update,
    }
    return self
end

function Table:setEngine(engine)
    self.options.engine = engine
    return self
end

function Table:setCharset(charset)
    self.options.charset = charset
    return self
end

function Table:setCollation(collation)
    self.options.collation = collation
    return self
end

function Table:toSQL(driver)
    local parts = {}

    for _, col in ipairs(self.columns) do
        local col_sql = "    " .. Quoting.quoteIdentifier(col._name) .. " " .. driver:mapType(col)
        if col._primary_key then
            col_sql = col_sql .. " PRIMARY KEY"
            -- Add AUTO_INCREMENT for databases that support it
            if col._auto_increment and driver:supportsAutoIncrement() then
                col_sql = col_sql .. " AUTO_INCREMENT"
            end
        end
        if not col._nullable and not col._primary_key then
            col_sql = col_sql .. " NOT NULL"
        end
        if col._unique and not col._primary_key then
            col_sql = col_sql .. " UNIQUE"
        end
        if col._default then
            if col._default == "CURRENT_TIMESTAMP" then
                col_sql = col_sql .. " DEFAULT CURRENT_TIMESTAMP"
            elseif type(col._default) == "string" then
                col_sql = col_sql .. " DEFAULT '" .. col._default:gsub("'", "''") .. "'"
            else
                col_sql = col_sql .. " DEFAULT " .. tostring(col._default)
            end
        end
        parts[#parts + 1] = col_sql
    end

    -- Add foreign key constraints
    for _, fk in ipairs(self.foreign_keys) do
        local fk_sql = string.format(
            "    FOREIGN KEY (%s) REFERENCES %s(%s)",
            Quoting.quoteIdentifier(fk.column),
            Quoting.quoteIdentifier(fk.references_table),
            Quoting.quoteIdentifier(fk.references_column)
        )
        if fk.on_delete then
            fk_sql = fk_sql .. " ON DELETE " .. fk.on_delete:upper()
        end
        if fk.on_update then
            fk_sql = fk_sql .. " ON UPDATE " .. fk.on_update:upper()
        end
        parts[#parts + 1] = fk_sql
    end

    local sql = string.format(
        "CREATE TABLE %s (\n%s\n)",
        Quoting.quoteIdentifier(self.name),
        table.concat(parts, ",\n")
    )

    -- Add table options (ENGINE, CHARSET, COLLATION)
    local options = {}
    if self.options.engine then
        options[#options + 1] = "ENGINE=" .. self.options.engine
    end
    if self.options.charset then
        options[#options + 1] = "CHARSET=" .. self.options.charset
    end
    if self.options.collation then
        options[#options + 1] = "COLLATE=" .. self.options.collation
    end

    if #options > 0 then
        sql = sql .. " " .. table.concat(options, " ")
    end

    return sql
end

-- Generate index statements separately (not concatenated with CREATE TABLE)
function Table:indexSQL()
    local statements = {}
    for _, idx in ipairs(self.indexes) do
        local idx_name = idx.name or (self.name .. "_idx_" .. table.concat(idx.columns, "_"))
        local unique = idx.unique and "UNIQUE " or ""
        local quoted_columns = {}
        for _, col in ipairs(idx.columns) do
            quoted_columns[#quoted_columns + 1] = Quoting.quoteIdentifier(col)
        end
        statements[#statements + 1] = string.format(
            "CREATE %sINDEX %s ON %s (%s)",
            unique,
            Quoting.quoteIdentifier(idx_name),
            Quoting.quoteIdentifier(self.name),
            table.concat(quoted_columns, ", ")
        )
    end
    return statements
end

return Table