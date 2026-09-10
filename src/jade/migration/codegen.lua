--- Shared Lua emission helpers for migration codegen.
--- Ensures generators emit the real Schema/Table API:
---   jade.createTable("name", function(t)
---     t:column("id", "integer", { primary_key = true, auto_increment = true })
---   end)
local M = {}

local function format_value(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end

--- Emit a single options-table key/value pair, or nil when value is absent.
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

--- Normalize column options into a deterministic ordered list of Lua assignments.
--- @param opts table|nil
--- @return string[]
function M.optionAssignments(opts)
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

--- Emit one `t:column(...)` call.
--- @param name string Column name
--- @param type_name string Jade type name (integer, string, ...)
--- @param opts table|nil
--- @param indent string|nil Line indent (default: 8 spaces)
--- @return string
function M.emitColumnCall(name, type_name, opts, indent)
    indent = indent or "        "
    local assignments = M.optionAssignments(opts)
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

--- Emit a complete `jade.createTable(...)` / `Jade.createTable(...)` block.
--- @param table_name string
--- @param columns table Array of { name, type, opts }
--- @param api_name string|nil Prefix used in the call (default: "jade")
--- @param indent string|nil Outer indent (default: 4 spaces)
--- @return string
function M.emitCreateTable(table_name, columns, api_name, indent)
    api_name = api_name or "jade"
    indent = indent or "    "
    local lines = {}
    lines[#lines + 1] = string.format('%s%s.createTable("%s", function(t)', indent, api_name, table_name)
    for _, col in ipairs(columns) do
        lines[#lines + 1] = M.emitColumnCall(col.name, col.type, col.opts, indent .. "    ")
    end
    lines[#lines + 1] = indent .. "end)"
    return table.concat(lines, "\n")
end

--- Sort column map keys for deterministic output. Primary keys first, then alpha.
--- @param columns table Map of name -> value
--- @return string[] names
function M.sortedColumnNames(columns)
    local names = {}
    for name in pairs(columns) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        local ka = columns[a]
        local kb = columns[b]
        local pa = type(ka) == "table" and (ka.primary_key or ka._primary_key) or false
        local pb = type(kb) == "table" and (kb.primary_key or kb._primary_key) or false
        if pa ~= pb then
            return pa
        end
        return a < b
    end)
    return names
end

--- Convert a Jade.Column instance (or plain table with underscore fields) to codegen opts.
--- Column uses underscore fields for state; bare names are fluent methods.
--- @param col table
--- @return table opts, string type_name
function M.columnToOpts(col)
    local type_name = col.type

    local function data(key, underscore_key)
        if underscore_key ~= nil and col[underscore_key] ~= nil then
            return col[underscore_key]
        end
        local v = col[key]
        if type(v) == "function" then
            return nil
        end
        return v
    end

    local primary_key = data("primary_key", "_primary_key")
    local unique = data("unique", "_unique")
    local auto_increment = data("auto_increment", "_auto_increment")
    local default = data("default", "_default")
    local default_now = data("default_now", "default_now")
    local references = data("references", "_references")

    local opts = {
        length = col.length,
        precision = col.precision,
        scale = col.scale,
    }

    if primary_key then
        opts.primary_key = true
    end
    if auto_increment then
        opts.auto_increment = true
    end
    if unique then
        opts.unique = true
    end
    if col._nullable == false or data("not_null", nil) == true or data("null", nil) == false then
        opts.null = false
    end

    if default == "CURRENT_TIMESTAMP" or default_now then
        opts.default_now = true
    elseif default ~= nil then
        opts.default = default
    end

    if references then
        opts.references = {
            table = references.table,
            column = references.column,
        }
    end

    return opts, type_name
end

--- Convert a declarative field table (parseModel / parseField output) to codegen opts.
--- @param field table
--- @return table opts, string type_name
function M.fieldToOpts(field)
    local type_name = field.type or "string"
    local opts = {
        length = field.length,
        precision = field.precision,
        scale = field.scale,
        unique = field.unique or nil,
        default = field.default,
        default_now = field.default_now or nil,
        references = field.references,
    }

    if field.primary_key then
        opts.primary_key = true
    end
    if field.not_null then
        opts.null = false
    end
    -- PK auto-increments unless explicitly disabled (matches generateEntity)
    if field.primary_key and field.auto_increment ~= false then
        opts.auto_increment = true
    end

    return opts, type_name
end

--- Convert an introspected column table to codegen opts.
--- @param col table
--- @return table opts, string type_name
function M.introspectedToOpts(col)
    local type_name = col.type or "string"
    local opts = {
        length = col.length,
        precision = col.precision,
        scale = col.scale,
    }

    if col.primary_key then
        opts.primary_key = true
    end
    if col.auto_increment then
        opts.auto_increment = true
    end
    if col.unique then
        opts.unique = true
    end
    if col.nullable == false or col.null == false then
        opts.null = false
    end

    if col.default == "CURRENT_TIMESTAMP" or col.default == "now()" then
        opts.default_now = true
    elseif col.default ~= nil and not col.auto_increment and not col.primary_key then
        local d = tostring(col.default):gsub("::%w+", "")
        if d == "true" then
            opts.default = true
        elseif d == "false" then
            opts.default = false
        elseif tonumber(d) then
            opts.default = tonumber(d)
        else
            local s = d:match("^'(.*)'$")
            if s then
                opts.default = s
            end
        end
    end

    return opts, type_name
end

return M
