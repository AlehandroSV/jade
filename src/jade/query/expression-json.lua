--- JSON extension for Expression objects.
-- Adds :jsonContains(), :jsonExists(), :jsonPath().
-- Loaded after Expression is defined via: require("jade.query.expression-json")(Expression)

local Quoting = require("jade.util.quoting")
local Json = require("jade.query.json")

return function(Expression)
    ----------------------------------------------------------------
    -- WHERE operators
    ----------------------------------------------------------------

    --- jsonContains(keyOrPath, value)
    --- Checks if JSON key/value exists (uses @> for PG, JSON_CONTAINS for MySQL).
    --- Escapes special characters in single-key paths to prevent injection.
    --- @param keyOrPath string|number JSON key or dot-path (e.g. "role" or "settings.theme")
    --- @param value any Value to search for
    --- @return Jade.Condition WHERE condition object matching JSON content
    Expression.jsonContains = function(self, keyOrPath, value)
        local p = tostring(keyOrPath):gsub("^%s*(.-)%s*$", "%1")
        local c = self._column or keyOrPath
        local Cond = require("jade.query.condition")

        -- Direct key (no dots) — simple JSON object lookup
        if not p:find(".") then
            local safeKey = p:gsub('"', '\\"'):gsub('\\', '\\\\')
            local safeVal = tostring(value):gsub('"', '\\"'):gsub('\\', '\\\\')
            return Cond.new(c, "@>", '{"' .. safeKey .. '": "' .. safeVal .. '"}', self._table)
        end

        -- Multi-level path — delegate to driver-specific SQL generator
        local segments = Json.parsePath(p)

        local makeCond = function(driver_type)
            local sql, bindings
            if driver_type == "postgresql" then
                sql, bindings = Json.pgJsonContainsSql(c, segments, value)
            elseif driver_type == "mysql" then
                sql, bindings = Json.myJsonContainsSql(c, segments, value)
            else
                sql, bindings = Json.sqliteJsonContainsSql(c, segments, value)
            end
            local cond = setmetatable({
                _json_where = true,
                _col = c,
                _sql = sql,
                _bindings = bindings,
                type = "simple",
            }, Cond)
            cond.compile = function(cond, out_bindings)
                local b = {}
                for _, v in ipairs(bindings) do b[#b + 1] = v end
                b[#b + 1] = value
                local prefix = (cond.table_name and cond.table_name ~= "") and Quoting.quoteIdentifier(cond.table_name) .. "." or ""
                return prefix .. sql, b
            end
            return cond
        end

        -- For now, default to PostgreSQL behavior
        return makeCond(driver_hint)
    end

    --- jsonExists(keyOrPath)
    --- Checks if a JSON key or nested path exists in the column.
    --- Uses the native `?` operator for PostgreSQL, JSON_CONTAINS_PATH for MySQL.
    --- @param keyOrPath string|number JSON key or dot-path (e.g. "theme" or "settings.theme")
    --- @return Jade.Condition WHERE condition object matching EXISTS check
    Expression.jsonExists = function(self, keyOrPath)
        local p = tostring(keyOrPath):gsub("^%s*(.-)%s*$", "%1")
        local c = self._column or keyOrPath
        local Cond = require("jade.query.condition")

        if not p:find(".") then
            return Cond.new(c, "?", p, self._table)
        end

        local segments = Json.parsePath(p)
        local driver_hint = self._driver_type or "postgresql"

        local makeCond = function(dt)
            local sql, bindings
            if dt == "postgresql" then
                sql, bindings = Json.pgJsonExistsSql(c, segments)
            elseif dt == "mysql" then
                sql, bindings = Json.myJsonExistsSql(c, segments)
            else
                sql, bindings = Json.sqliteJsonExistsSql(c, segments)
            end
            local cond = setmetatable({
                _json_where = true,
                _col = c,
                _sql = sql,
                _bindings = bindings,
                type = "simple",
            }, Cond)
            cond.compile = function(cond, out_bindings)
                local b = {}
                for _, v in ipairs(bindings) do b[#b + 1] = v end
                local prefix = (cond.table_name and cond.table_name ~= "") and Quoting.quoteIdentifier(cond.table_name) .. "." or ""
                return prefix .. sql, b
            end
            return cond
        end

        return makeCond(driver_hint)
    end

    ----------------------------------------------------------------
    -- SELECT / ORDER BY / GROUP BY expressions
    ----------------------------------------------------------------

    --- jsonPath(path, [asText])
    --- Extracts a value from JSON column for use in SELECT, ORDER BY, etc.
    --- Returns a lightweight marker table recognised by drivers via `_raw_json`.
    --- Supports nested dot-paths and bracket array notation (e.g. "a.b[0].c").
    --- @param pathStr string Dot-path or bracketed path into JSON (e.g. "email" or "settings.theme")
    --- @param asText? boolean If true, cast to text (PG `->>`, MySQL `JSON_UNQUOTE`)
    --- @return { _raw_json: boolean, _pathSegments: any[], _asText: boolean, _jsonColumn: string }
    Expression.jsonPath = function(self, pathStr, asText)
        local p = tostring(pathStr):gsub("^%s*(.-)%s*$", "%1")
        local asTextFlag = asText == true
        local segments = Json.parsePath(p)

        return {
            _raw_json = true,
            _pathSegments = segments,
            _asText = asTextFlag,
            _jsonColumn = self._column or pathStr,
        }
    end

    -- jsonSet, jsonRemove, jsonMerge — deferred to future PR (update operations)
end

