--- JSON operator helpers for PostgreSQL (JSONB), MySQL (JSON) and SQLite.
-- Provides path parsing and SQL fragment generation per driver type.

local Quoting = require("jade.util.quoting")

local M = {}

--- Parse a dot-path string into an array of segments.
-- Supports bracket notation: 'a.b[0].c' -> {'a', 'b', 0, 'c'}
M.parsePath = function(pathStr)
    local result = {}
    local current = ""
    local i = 1
    while i <= #pathStr do
        local ch = pathStr:sub(i, i)
        if ch == "." then
            if current ~= "" then result[#result + 1] = current end
            current = ""
        elseif ch == "[" then
            if current ~= "" then result[#result + 1] = current end
            i = i + 1
            local num = ""
            while i <= #pathStr and pathStr:sub(i, i) ~= "]" do
                num = num .. pathStr:sub(i, i)
                i = i + 1
            end
            if num ~= "" and tonumber(num) then
                result[#result + 1] = tonumber(num)
            else
                result[#result + 1] = num
            end
            current = ""
        else
            current = current .. ch
        end
        i = i + 1
    end
    if current ~= "" then result[#result + 1] = current end
    return result
end

--- Generate PostgreSQL JSONB SQL fragment for SELECT/ORDER BY/GROUP BY usage.
-- Uses -> (binary) or ->> (text). Returns {sql, bindings}.
M.pgSelectSql = function(colName, pathSegments, targetIsText)
    local sql = Quoting.quoteIdentifier(colName)
    local bindings = {}
    for _, seg in ipairs(pathSegments) do
        if type(seg) == "number" then
            sql = sql .. " -> " .. tostring(seg)
            if targetIsText then sql = sql .. " :: text" end
        else
            bindings[#bindings + 1] = seg
            if targetIsText then
                sql = sql .. " ->> ?"
            else
                sql = sql .. " -> ?"
            end
        end
    end
    return sql, bindings
end

--- Generate MySQL JSON SQL fragment for SELECT/ORDER BY/GROUP BY usage.
-- Uses JSON_EXTRACT / JSON_UNQUOTE(JSON_EXTRACT). Returns {sql, bindings}.
M.mySelectSql = function(colName, pathSegments, targetIsText)
    local jsonPath = "$"
    for _, seg in ipairs(pathSegments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    local expr = Quoting.quoteIdentifier(colName) .. ", '" .. jsonPath .. "'"
    if targetIsText then
        return "JSON_UNQUOTE(JSON_EXTRACT(" .. expr .. "))", {}
    end
    return "JSON_EXTRACT(" .. expr .. ")", {}
end

--- Generate SQLite JSON SQL fragment. Limited support via json_extract().
M.sqliteSelectSql = function(colName, pathSegments, targetIsText)
    local jsonPath = "$"
    for _, seg in ipairs(pathSegments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    local expr = Quoting.quoteIdentifier(colName) .. ", '" .. jsonPath .. "'"
    if targetIsText then
        return "CAST(json_extract(" .. expr .. ") AS TEXT)", {}
    end
    return "json_extract(" .. expr .. ")", {}
end

--- Generate WHERE condition SQL for Postgres: key @> value
M.pgJsonContainsSql = function(colName, pathSegments, boundValue)
    local sql = Quoting.quoteIdentifier(colName) .. " @> ?"
    -- Bind value as JSONB literal string
    return sql, {boundValue}
end

--- Generate WHERE condition SQL for MySQL: JSON_CONTAINS(col, value, path)
M.myJsonContainsSql = function(colName, pathSegments, boundValue)
    local jsonPath = "$"
    for _, seg in ipairs(pathSegments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    return "JSON_CONTAINS(" .. Quoting.quoteIdentifier(colName) .. ", ?, '" .. jsonPath .. "')", {boundValue}
end

--- Generate WHERE condition SQL for SQLite: json_extract(col, '$.key') = value
M.sqliteJsonContainsSql = function(colName, pathSegments, boundValue)
    local jsonPath = "$"
    for _, seg in ipairs(pathSegments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    return "json_extract(" .. Quoting.quoteIdentifier(colName) .. ", '" .. jsonPath .. "') = ?", {boundValue}
end

--- Generate WHERE condition SQL for Postgres: key ? 'path' (exists)
M.pgJsonExistsSql = function(colName, segments)
    -- PostgreSQL native JSONB ? operator: '{"key"}' ?| '{array}'
    -- Use LIKE-based check via cast
    local pathStr = "'" .. table.concat(segments, "', '") .. "'"
    return Quoting.quoteIdentifier(colName) .. " ? ?", {pathStr}
end

--- Generate WHERE condition SQL for MySQL: JSON_CONTAINS_PATH(col, mode, path)
M.myJsonExistsSql = function(colName, segments)
    local jsonPath = "$"
    for _, seg in ipairs(segments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    return "JSON_CONTAINS_PATH(" .. Quoting.quoteIdentifier(colName) .. ", 'one', '" .. jsonPath .. "')", {}
end

--- Generate WHERE condition SQL for SQLite: exists check via length
M.sqliteJsonExistsSql = function(colName, segments)
    local jsonPath = "$"
    for _, seg in ipairs(segments) do
        if type(seg) == "number" then
            jsonPath = jsonPath .. "[" .. tostring(seg) .. "]"
        else
            jsonPath = jsonPath .. "." .. seg
        end
    end
    return "json_length(json_extract(" .. Quoting.quoteIdentifier(colName) .. ", '" .. jsonPath .. "')) > 0", {}
end

return M

