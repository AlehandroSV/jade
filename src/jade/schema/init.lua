local Quoting = require("jade.util.quoting")

local Schema = {}

-- DDL operations that execute SQL directly
function Schema.createTable(driver, name, fn)
    local Table = require("jade.schema.table")
    local tbl = Table.new(name)
    fn(tbl)

    -- Execute CREATE TABLE
    local sql = tbl:toSQL(driver)
    driver:execute(sql)

    -- Execute CREATE INDEX statements separately
    local index_statements = tbl:indexSQL(driver)
    for _, idx_sql in ipairs(index_statements) do
        driver:execute(idx_sql)
    end

    return true
end

function Schema.dropTable(driver, name)
    local sql = "DROP TABLE IF EXISTS " .. driver:quoteIdentifier(name)
    if driver:dropTableCascade() then
        sql = sql .. " CASCADE"
    end
    driver:execute(sql)
    return true
end

function Schema.renameTable(driver, old_name, new_name)
    local sql = "ALTER TABLE " .. driver:quoteIdentifier(old_name) .. " RENAME TO " .. driver:quoteIdentifier(new_name)
    driver:execute(sql)
    return true
end

function Schema.addColumn(driver, table_name, column_name, type_name, options)
    options = options or {}
    local sql = "ALTER TABLE " .. driver:quoteIdentifier(table_name) .. " ADD COLUMN " .. driver:quoteIdentifier(column_name) .. " " .. type_name

    if options.length then
        sql = sql .. "(" .. options.length .. ")"
    end
    if options.null == false then
        sql = sql .. " NOT NULL"
    end
    if options.default ~= nil then
        if type(options.default) == "string" then
            sql = sql .. " DEFAULT '" .. options.default:gsub("'", "''") .. "'"
        else
            sql = sql .. " DEFAULT " .. tostring(options.default)
        end
    end

    driver:execute(sql)
    return true
end

function Schema.dropColumn(driver, table_name, column_name)
    local sql = "ALTER TABLE " .. driver:quoteIdentifier(table_name) .. " DROP COLUMN " .. driver:quoteIdentifier(column_name)
    driver:execute(sql)
    return true
end

function Schema.renameColumn(driver, table_name, old_name, new_name)
    local sql = "ALTER TABLE " .. driver:quoteIdentifier(table_name) .. " RENAME COLUMN " .. driver:quoteIdentifier(old_name) .. " TO " .. driver:quoteIdentifier(new_name)
    driver:execute(sql)
    return true
end

function Schema.addIndex(driver, table_name, columns, options)
    options = options or {}
    if type(columns) == "string" then
        columns = { columns }
    end

    local index_name = options.name or (table_name .. "_idx_" .. table.concat(columns, "_"))
    local unique = options.unique and "UNIQUE " or ""

    local quoted_columns = {}
    for _, col in ipairs(columns) do
        quoted_columns[#quoted_columns + 1] = driver:quoteIdentifier(col)
    end

    local sql = string.format(
        "CREATE %sINDEX %s ON %s (%s)",
        unique,
        driver:quoteIdentifier(index_name),
        driver:quoteIdentifier(table_name),
        table.concat(quoted_columns, ", ")
    )

    driver:execute(sql)
    return true
end

function Schema.dropIndex(driver, table_name, index_name)
    local sql = "DROP INDEX IF EXISTS " .. driver:quoteIdentifier(index_name)
    driver:execute(sql)
    return true
end

function Schema.addForeignKey(driver, table_name, options)
    local constraint_name = options.constraint_name or (table_name .. "_fk_" .. options.column)
    local sql = string.format(
        "ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s)",
        driver:quoteIdentifier(table_name),
        driver:quoteIdentifier(constraint_name),
        driver:quoteIdentifier(options.column),
        driver:quoteIdentifier(options.references_table),
        driver:quoteIdentifier(options.references_column or "id")
    )

    if options.on_delete then
        sql = sql .. " ON DELETE " .. options.on_delete:upper()
    end
    if options.on_update then
        sql = sql .. " ON UPDATE " .. options.on_update:upper()
    end

    driver:execute(sql)
    return true
end

function Schema.dropForeignKey(driver, table_name, constraint_name)
    local sql = string.format(
        "ALTER TABLE %s DROP CONSTRAINT %s",
        driver:quoteIdentifier(table_name),
        driver:quoteIdentifier(constraint_name)
    )
    driver:execute(sql)
    return true
end

return Schema