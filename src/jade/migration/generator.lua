local M = {}

local function format_value(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

local function option_entry(key, value)
    if value == nil then
        return nil
    end
    if type(value) == "boolean" then
        return key .. " = " .. tostring(value)
    end
    if type(value) == "table" then
        local parts = {}
        for k, v in pairs(value) do
            parts[#parts + 1] = string.format("%s = %s", k, format_value(v))
        end
        table.sort(parts)
        return key .. " = { " .. table.concat(parts, ", ") .. " }"
    end
    return key .. " = " .. format_value(value)
end

local function optionAssignments(opts)
    opts = opts or {}
    local order = {
        "length",
        "precision",
        "scale",
        "primary_key",
        "auto_increment",
        "unique",
        "null",
        "default",
        "default_now",
        "references",
    }
    local assignments = {}
    for _, key in ipairs(order) do
        local entry = option_entry(key, opts[key])
        if entry then
            assignments[#assignments + 1] = entry
        end
    end
    return assignments
end

local function columnToOpts(col)
    local opts = {
        length = col.length,
        precision = col.precision,
        scale = col.scale,
    }

    if col._primary_key then
        opts.primary_key = true
    end
    if col._auto_increment then
        opts.auto_increment = true
    end
    if col._unique then
        opts.unique = true
    end
    if col._nullable == false then
        opts.null = false
    end
    if col._default == "CURRENT_TIMESTAMP" then
        opts.default_now = true
    elseif col._default ~= nil then
        opts.default = col._default
    end
    if col._references then
        opts.references = {
            table = col._references.table,
            column = col._references.column,
        }
    end

    return opts, col.type
end

local function sortedColumnNames(columns)
    local names = {}
    for name in pairs(columns) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        local ka = columns[a]
        local kb = columns[b]
        local pa = type(ka) == "table" and (ka._primary_key or ka.primary_key)
        local pb = type(kb) == "table" and (kb._primary_key or kb.primary_key)
        if pa ~= pb then
            return pa and true or false
        end
        return a < b
    end)
    return names
end

local function emitColumnCall(name, type_name, opts, indent)
    indent = indent or "        "
    local assignments = optionAssignments(opts)
    if #assignments == 0 then
        return string.format('%st:column(%s, %s)', indent, format_value(name), format_value(type_name))
    end
    return string.format(
        '%st:column(%s, %s, { %s })',
        indent,
        format_value(name),
        format_value(type_name),
        table.concat(assignments, ", ")
    )
end

--- Build the options table text for Jade.addColumn, or nil when empty.
local function addColumnOptionsText(column)
    local opts = select(1, columnToOpts(column))
    local assignments = optionAssignments(opts)
    if #assignments == 0 then
        return nil
    end
    return "{ " .. table.concat(assignments, ", ") .. " }"
end

function M.generateCreateTable(table_name, columns)
    local lines = {}
    lines[#lines + 1] = '    Jade.createTable("' .. table_name .. '", function(t)'

    for _, name in ipairs(sortedColumnNames(columns)) do
        local col = columns[name]
        local opts, type_name = columnToOpts(col)
        lines[#lines + 1] = emitColumnCall(name, type_name, opts, "        ")
    end

    lines[#lines + 1] = "    end)"

    return table.concat(lines, "\n")
end

function M.generateDropTable(table_name)
    return '    Jade.dropTable("' .. table_name .. '")'
end

function M.generateAddColumn(table_name, column_name, column)
    local type_name = column.type
    local opts_text = addColumnOptionsText(column)
    if opts_text then
        return string.format(
            '    Jade.addColumn("%s", "%s", "%s", %s)',
            table_name,
            column_name,
            type_name,
            opts_text
        )
    end
    return string.format(
        '    Jade.addColumn("%s", "%s", "%s")',
        table_name,
        column_name,
        type_name
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
