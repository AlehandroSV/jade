local Codegen = require("jade.migration.codegen")

local M = {}

function M.generateCreateTable(table_name, columns)
    local ordered = {}
    for _, name in ipairs(Codegen.sortedColumnNames(columns)) do
        local col = columns[name]
        local opts, type_name = Codegen.columnToOpts(col)
        ordered[#ordered + 1] = {
            name = name,
            type = type_name,
            opts = opts,
        }
    end
    return Codegen.emitCreateTable(table_name, ordered, "Jade", "    ")
end

function M.generateDropTable(table_name)
    return '    Jade.dropTable("' .. table_name .. '")'
end

function M.generateAddColumn(table_name, column_name, column)
    local opts, type_name = Codegen.columnToOpts(column)
    local assignments = Codegen.optionAssignments(opts)
    -- length already covered by optionAssignments; drop precision/scale noise for ALTER
    if #assignments == 0 then
        return string.format('    Jade.addColumn("%s", "%s", "%s")', table_name, column_name, type_name)
    end
    return string.format(
        '    Jade.addColumn("%s", "%s", "%s", { %s })',
        table_name,
        column_name,
        type_name,
        table.concat(assignments, ", ")
    )
end

function M.generateDropColumn(table_name, column_name)
    return '    Jade.dropColumn("' .. table_name .. '", "' .. column_name .. '")'
end

function M.generateMigration(name, diff)
    local up_lines = {}
    local down_lines = {}

    -- Create tables
    for _, tbl in ipairs(diff.create_tables) do
        up_lines[#up_lines + 1] = M.generateCreateTable(tbl.name, tbl.columns)
        down_lines[#down_lines + 1] = M.generateDropTable(tbl.name)
    end

    -- Drop tables
    for _, table_name in ipairs(diff.drop_tables) do
        up_lines[#up_lines + 1] = M.generateDropTable(table_name)
        -- Note: we can't easily reverse this without knowing the schema
        down_lines[#down_lines + 1] = '-- TODO: recreate table ' .. table_name
    end

    -- Add columns
    for _, change in ipairs(diff.add_columns) do
        up_lines[#up_lines + 1] = M.generateAddColumn(change.table, change.column.name, change.column)
        down_lines[#down_lines + 1] = M.generateDropColumn(change.table, change.column.name)
    end

    -- Drop columns
    for _, change in ipairs(diff.drop_columns) do
        up_lines[#up_lines + 1] = M.generateDropColumn(change.table, change.column)
        -- Note: we can't easily reverse this without knowing the column definition
        down_lines[#down_lines + 1] = '-- TODO: recreate column ' .. change.table .. '.' .. change.column
    end

    -- Modify columns (simplified - just drop and re-add)
    for _, change in ipairs(diff.modify_columns) do
        up_lines[#up_lines + 1] = '-- TODO: modify column ' .. change.table .. '.' .. change.column.name
        down_lines[#down_lines + 1] = '-- TODO: modify column ' .. change.table .. '.' .. change.column.name
    end

    local up_content = table.concat(up_lines, "\n\n")
    local down_content = table.concat(down_lines, "\n\n")

    return up_content, down_content
end

return M
