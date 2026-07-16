local Schema = {}

-- DDL operations that execute SQL directly
function Schema.createTable(driver, name, fn)
    local Table = require("jade.schema.table")
    local tbl = Table.new(name)
    fn(tbl)
    local sql = tbl:toSQL(driver)
    driver:execute(sql)
    return true
end

function Schema.dropTable(driver, name)
    local sql = "DROP TABLE IF EXISTS " .. name .. " CASCADE"
    driver:execute(sql)
    return true
end

function Schema.renameTable(driver, old_name, new_name)
    local sql = "ALTER TABLE " .. old_name .. " RENAME TO " .. new_name
    driver:execute(sql)
    return true
end

function Schema.addColumn(driver, table_name, column_name, type_name, options)
    options = options or {}
    local sql = "ALTER TABLE " .. table_name .. " ADD COLUMN " .. column_name .. " " .. type_name

    if options.length then
        sql = sql .. "(" .. options.length .. ")"
    end
    if options.null == false then
        sql = sql .. " NOT NULL"
    end
    if options.default ~= nil then
        sql = sql .. " DEFAULT " .. tostring(options.default)
    end

    driver:execute(sql)
    return true
end

function Schema.dropColumn(driver, table_name, column_name)
    local sql = "ALTER TABLE " .. table_name .. " DROP COLUMN " .. column_name
    driver:execute(sql)
    return true
end

function Schema.renameColumn(driver, table_name, old_name, new_name)
    local sql = "ALTER TABLE " .. table_name .. " RENAME COLUMN " .. old_name .. " TO " .. new_name
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

    local sql = string.format(
        "CREATE %sINDEX %s ON %s (%s)",
        unique,
        index_name,
        table_name,
        table.concat(columns, ", ")
    )

    driver:execute(sql)
    return true
end

function Schema.dropIndex(driver, table_name, index_name)
    local sql = "DROP INDEX IF EXISTS " .. index_name
    driver:execute(sql)
    return true
end

function Schema.addForeignKey(driver, table_name, options)
    local sql = string.format(
        "ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s(%s)",
        table_name,
        options.constraint_name or (table_name .. "_fk_" .. options.column),
        options.column,
        options.references_table,
        options.references_column or "id"
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
        table_name,
        constraint_name
    )
    driver:execute(sql)
    return true
end

return Schema