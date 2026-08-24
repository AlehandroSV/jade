local Expression = require("jade.query.expression")
local Condition = require("jade.query.condition")
local Instance = require("jade.entity.instance")
local Quoting = require("jade.util.quoting")
local Security = require("jade.security")

local Query = {}
Query.__index = Query

function Query.new(entity)
    return setmetatable({
        _entity = entity,
        _table = entity._table,
        _where = {},
        _orderBy = {},
        _limit = nil,
        _offset = nil,
        _select = {},
        _includes = {},
        _bindings = {},
        _joins = {},
        _groupBy = {},
        _having = {},
        _distinct = false,
        _cache_ttl = nil,
        _cache_key = nil,
        _timeout = nil,
        _include_trashed = false,
        _only_trashed = false,
        _where_explicit = false,
    }, Query)
end

--- Deep-copy mutable array fields from source into dest Query.
local function _copyArrays(src, dst)
    if not src or not dst then return end
    for _, key in ipairs({ "_where", "_orderBy", "_select", "_bindings", "_joins", "_groupBy", "_having" }) do
        local v = src[key]
        if type(v) == "table" then
            dst[key] = {}
            for i = 1, #v do dst[key][i] = v[i] end
        end
    end
end

--- Clone scalar fields from source into dest Query.
local function _copyScalars(src, dst)
    dst._entity = src._entity; dst._table = src._table
    dst._limit = src._limit; dst._offset = src._offset
    dst._includes = src._includes; dst._distinct = src._distinct
    dst._cache_ttl = src._cache_ttl; dst._cache_key = src._cache_key
    dst._timeout = src._timeout
    dst._include_trashed = src._include_trashed
    dst._only_trashed = src._only_trashed
    dst._where_explicit = src._where_explicit
end

-- Set query timeout in milliseconds
function Query:timeout(ms)
    if type(ms) ~= "number" or ms <= 0 then
        error("Timeout must be a positive number in milliseconds")
    end
    self._timeout = ms
    return self
end

-- Include soft-deleted records in results
function Query:withTrashed()
    self._include_trashed = true
    self._only_trashed = false
    return self
end

-- Return only soft-deleted records
function Query:onlyTrashed()
    self._include_trashed = false
    self._only_trashed = true
    return self
end

function Query:where(condition)
    if type(condition) == "table" and condition._raw and not condition.compile then
        local raw_sql = condition._raw
        local raw_bindings = condition._bindings or {}

        -- Validate raw SQL for dangerous patterns
        if type(raw_sql) ~= "string" then
            error("Raw condition SQL must be a string")
        end

        -- Only validate when we have an actual string (some callers may pass other types)
        if type(raw_sql) == "string" and #raw_sql > 0 then
            local upper = raw_sql:upper()

            -- Block UNION/UNION ALL SELECT — prevents result-set manipulation
            if upper:match("UNION%s+ALL%s+SELECT") or upper:match("UNION%s+SELECT") then
                error("Raw WHERE condition does not allow UNION SELECT")
            end

            -- Block destructive DDL/DML via semicolon injection
            -- Pattern: ; followed by keyword (Lua patterns use %s for space)
            local bad_kw = upper:match(";[%s]*DROP[%s(]") and "DROP" or
                           upper:match(";[%s]*DELETE[%s]+FROM") and "DELETE" or
                           upper:match(";[%s]*UPDATE[%s]") and "UPDATE" or
                           upper:match(";[%s]*ALTER[%s(]") and "ALTER" or
                           upper:match(";[%s]*TRUNCATE[%s]") and "TRUNCATE" or
                           upper:match(";[%s]*INSERT[%s]+INTO") and "INSERT" or
                           upper:match(";[%s]*CREATE[%s(]") and "CREATE" or
                           upper:match(";[%s]*GRANT[%s]") and "GRANT" or
                           upper:match(";[%s]*REVOKE[%s]") and "REVOKE" or
                           upper:match(";[%s]*EXECUTE[%s]") and "EXECUTE" or
                           upper:match(";[%s]*EXEC[%s]") and "EXEC"
            if bad_kw then
                error("Raw WHERE condition does not allow '" .. bad_kw .. "' statements")
            end
        end

        condition = {
            _raw = raw_sql,
            _bindings = raw_bindings,
            compile = function(self, bindings_out)
                bindings_out = bindings_out or {}
                for _, v in ipairs(self._bindings) do
                    bindings_out[#bindings_out + 1] = v
                end
                return self._raw, bindings_out
            end,
            band = function(self, other)
                return setmetatable({ left = self, right = other, type = "and" }, { __index = Condition })
            end,
            bor = function(self, other)
                return setmetatable({ left = self, right = other, type = "or" }, { __index = Condition })
            end,
        }
    end

    -- Flag set even for non-filtering conditions (e.g. raw("1=1")).
    -- The user's intent to filter is explicit, which is what matters.
    self._where_explicit = true
    self._where[#self._where + 1] = condition
    return self
end

function Query:orderBy(column, direction)
    local col_name = column
    local dir = direction or "ASC"

    if type(column) == "table" and column._column then
        col_name = column._column
    end

    -- Validate column name and direction
    Security.validateOrderBy(col_name, dir)

    self._orderBy[#self._orderBy + 1] = { column = col_name, dir = dir }
    return self
end

function Query:limit(n)
    Security.validateLimit(n)
    self._limit = n
    return self
end

function Query:offset(n)
    Security.validateOffset(n)
    self._offset = n
    return self
end

function Query:select(...)
    local cols = { ... }
    if #cols == 1 and type(cols[1]) == "table" then
        cols = cols[1]
    end
    for _, col in ipairs(cols) do
        Security.validateSelectItem(col)
        self._select[#self._select + 1] = col
    end
    return self
end

function Query:include(relation_name)
    self._includes[#self._includes + 1] = relation_name
    return self
end

function Query:distinct()
    self._distinct = true
    return self
end

function Query:join(table_name, on_condition)
    Security.validateJoinTableName(table_name)
    self._joins[#self._joins + 1] = { type = "INNER", table = table_name, on = on_condition }
    return self
end

function Query:leftJoin(table_name, on_condition)
    Security.validateJoinTableName(table_name)
    self._joins[#self._joins + 1] = { type = "LEFT", table = table_name, on = on_condition }
    return self
end

function Query:rightJoin(table_name, on_condition)
    Security.validateJoinTableName(table_name)
    self._joins[#self._joins + 1] = { type = "RIGHT", table = table_name, on = on_condition }
    return self
end

function Query:innerJoin(table_name, on_condition)
    Security.validateJoinTableName(table_name)
    self._joins[#self._joins + 1] = { type = "INNER", table = table_name, on = on_condition }
    return self
end

function Query:groupBy(...)
    local cols = { ... }
    if #cols == 1 and type(cols[1]) == "table" then
        cols = cols[1]
    end
    for _, col in ipairs(cols) do
        self._groupBy[#self._groupBy + 1] = col
    end
    return self
end

function Query:having(condition)
    self._having[#self._having + 1] = condition
    return self
end

function Query:cache(ttl, key)
    self._cache_ttl = ttl
    self._cache_key = key
    return self
end

function Query:get()
    -- Check cache if enabled
    if self._cache_ttl then
        local Cache = require("jade.cache")
        local cache_key = self._cache_key or Cache.keygen(self._table, { self:toSQL() })
        local cached = Cache.get(cache_key)
        if cached then return cached end
    end

    local sql, bindings = self:toSQL()
    local driver = self._entity._driver

    -- Apply timeout if set (per-query or global)
    local timeout_ms = self:_resolveTimeout()
    if timeout_ms then
        driver:setQueryTimeout(timeout_ms)
    end

    local raw = driver:execute(sql, bindings)

    -- Reset timeout after execution
    if timeout_ms then
        driver:clearQueryTimeout()
    end

    local instances = {}

    -- Handle custom encryption decryption at Lua level
    local Encryption = require("jade.encryption")
    local is_custom = Encryption.isEnabled() and Encryption.isCustom()

    for i, row in ipairs(raw) do
        -- Decrypt custom-encrypted fields
        if is_custom then
            row = Encryption.decryptFields(self._entity._table, row, self._entity._columns)
        end
        instances[i] = Instance.new(self._entity, row)
    end

    -- Eager load included relations
    if #self._includes > 0 then
        self:_eagerLoad(instances)
    end

    -- Store in cache if enabled
    if self._cache_ttl then
        local Cache = require("jade.cache")
        local cache_key = self._cache_key or Cache.keygen(self._table, { self:toSQL() })
        Cache.set(cache_key, instances, self._cache_ttl)
    end

    return instances
end

-- Resolve timeout: per-query takes priority over global config
function Query:_resolveTimeout()
    if self._timeout then
        return self._timeout
    end
    local ok, config = pcall(require, "jade.config")
    if ok then
        local cfg = config.get()
        if cfg and cfg.query_timeout then
            return cfg.query_timeout
        end
    end
    return nil
end

-- Get list of available relation names on the entity
function Query:_getRelationNames()
    local names = {}
    for name in pairs(self._entity._relations) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function Query:_eagerLoad(instances)
    if #self._includes == 0 then return end

    -- Validate all included relations exist before loading
    for _, rel_name in ipairs(self._includes) do
        local relation = self._entity._relations[rel_name]
        if not relation then
            local available = table.concat(self:_getRelationNames(), ", ")
            error(string.format(
                "Relation '%s' not found on entity '%s'. Available relations: %s",
                rel_name,
                self._entity._table,
                available
            ))
        end
    end

    if #instances == 0 then return end

    for _, rel_name in ipairs(self._includes) do
        local relation = self._entity._relations[rel_name]
        if relation then
            if relation.type == "belongsTo" then
                -- belongsTo: load from target table where target.id = source.foreign_key
                local ids = {}
                for _, inst in ipairs(instances) do
                    local fk = inst._data[relation.foreign_key]
                    if fk ~= nil then
                        ids[#ids + 1] = fk
                    end
                end

                if #ids > 0 then
                    local target_entity = relation.target
                    local q = Query.new(target_entity)
                    q._where = { Expression.new("id", target_entity._table):isIn(ids) }
                    local related = q:get()

                    local grouped = {}
                    for _, r in ipairs(related) do
                        grouped[r._data.id] = r
                    end

                    for _, inst in ipairs(instances) do
                        local fk = inst._data[relation.foreign_key]
                        inst._data[rel_name] = grouped[fk] or nil
                    end
                end

            elseif relation.type == "hasOne" then
                -- hasOne: load from target table where target.foreign_key = source.id
                local ids = {}
                for _, inst in ipairs(instances) do
                    ids[#ids + 1] = inst._data.id
                end

                if #ids > 0 then
                    local target_entity = relation.target
                    local q = Query.new(target_entity)
                    q._where = { Expression.new(relation.foreign_key, target_entity._table):isIn(ids) }
                    local related = q:get()

                    local grouped = {}
                    for _, r in ipairs(related) do
                        local key = r._data[relation.foreign_key]
                        if key then
                            grouped[key] = r
                        end
                    end

                    for _, inst in ipairs(instances) do
                        inst._data[rel_name] = grouped[inst._data.id] or nil
                    end
                end

            elseif relation.type == "hasMany" then
                -- hasMany: load from target table where target.foreign_key = source.id
                local ids = {}
                for _, inst in ipairs(instances) do
                    ids[#ids + 1] = inst._data.id
                end

                if #ids > 0 then
                    local target_entity = relation.target
                    local q = Query.new(target_entity)
                    q._where = { Expression.new(relation.foreign_key, target_entity._table):isIn(ids) }
                    local related = q:get()

                    local grouped = {}
                    for _, r in ipairs(related) do
                        local key = r._data[relation.foreign_key]
                        if key then
                            if not grouped[key] then grouped[key] = {} end
                            grouped[key][#grouped[key] + 1] = r
                        end
                    end

                    for _, inst in ipairs(instances) do
                        inst._data[rel_name] = grouped[inst._data.id] or {}
                    end
                end

            elseif relation.type == "hasAndBelongsToMany" then
                -- hasAndBelongsToMany: query pivot table first, then load targets
                local source_ids = {}
                for _, inst in ipairs(instances) do
                    source_ids[#source_ids + 1] = inst._data[relation.source_key]
                end

                if #source_ids > 0 then
                    local driver = self._entity._driver

                    -- Query pivot table to get mappings
                    local pivot_sql = string.format(
                        "SELECT %s, %s FROM %s WHERE %s IN (%s)",
                        Quoting.quoteIdentifier(relation.source_foreign_key),
                        Quoting.quoteIdentifier(relation.target_foreign_key),
                        Quoting.quoteIdentifier(relation.join_table),
                        Quoting.quoteIdentifier(relation.source_foreign_key),
                        string.rep("?", #source_ids)
                    )
                    local pivot_result = driver:execute(pivot_sql, source_ids)

                    -- Collect target IDs grouped by source ID
                    local source_to_targets = {}
                    local all_target_ids = {}
                    for _, row in ipairs(pivot_result) do
                        local source_id = row[relation.source_foreign_key]
                        local target_id = row[relation.target_foreign_key]
                        if source_id and target_id then
                            if not source_to_targets[source_id] then
                                source_to_targets[source_id] = {}
                            end
                            source_to_targets[source_id][#source_to_targets[source_id] + 1] = target_id
                            all_target_ids[#all_target_ids + 1] = target_id
                        end
                    end

                    -- Load target records
                    if #all_target_ids > 0 then
                        local target_entity = relation.target
                        local q = Query.new(target_entity)
                        q._where = { Expression.new(relation.target_key, target_entity._table):isIn(all_target_ids) }
                        local targets = q:get()

                        local target_map = {}
                        for _, t in ipairs(targets) do
                            target_map[t._data[relation.target_key]] = t
                        end

                        -- Group targets by source ID
                        for source_id, target_ids in pairs(source_to_targets) do
                            local grouped = {}
                            for _, target_id in ipairs(target_ids) do
                                if target_map[target_id] then
                                    grouped[#grouped + 1] = target_map[target_id]
                                end
                            end
                            source_to_targets[source_id] = grouped
                        end
                    end

                    -- Attach to instances
                    for _, inst in ipairs(instances) do
                        local source_id = inst._data[relation.source_key]
                        inst._data[rel_name] = source_to_targets[source_id] or {}
                    end
                end

            elseif relation.type == "hasManyThrough" then
                -- hasManyThrough: load via intermediate table
                local source_ids = {}
                for _, inst in ipairs(instances) do
                    source_ids[#source_ids + 1] = inst._data.id
                end

                if #source_ids > 0 then
                    local through_entity = relation.through
                    local target_entity = relation.target

                    -- Load through records
                    local through_q = Query.new(through_entity)
                    through_q._where = { Expression.new(relation.source_foreign_key, through_entity._table):isIn(source_ids) }
                    local through_records = through_q:get()

                    -- Collect target IDs
                    local target_ids = {}
                    for _, through_rec in ipairs(through_records) do
                        local target_id = through_rec._data[relation.target_foreign_key]
                        if target_id then
                            target_ids[#target_ids + 1] = target_id
                        end
                    end

                    if #target_ids > 0 then
                        -- Load target records
                        local target_q = Query.new(target_entity)
                        target_q._where = { Expression.new("id", target_entity._table):isIn(target_ids) }
                        local targets = target_q:get()

                        local target_map = {}
                        for _, t in ipairs(targets) do
                            target_map[t._data.id] = t
                        end

                        -- Group by source ID
                        local grouped = {}
                        for _, through_rec in ipairs(through_records) do
                            local source_id = through_rec._data[relation.source_foreign_key]
                            local target_id = through_rec._data[relation.target_foreign_key]
                            if source_id and target_id and target_map[target_id] then
                                if not grouped[source_id] then grouped[source_id] = {} end
                                grouped[source_id][#grouped[source_id] + 1] = target_map[target_id]
                            end
                        end

                        for _, inst in ipairs(instances) do
                            inst._data[rel_name] = grouped[inst._data.id] or {}
                        end
                    end
                end
            end
        end
    end
end

function Query:first()
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._limit = 1
    return q:get()[1]
end

function Query:find(id)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._where = { Condition.new("id", "=", id, self._table) }
    q._limit = 1
    q._timeout = self._timeout
    q._include_trashed = self._include_trashed
    q._only_trashed = self._only_trashed
    return q:get()[1]
end

function Query:count()
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { "COUNT(*) as count" }
    local sql, bindings = q:toSQL()
    return q._entity._driver:execute(sql, bindings)[1] and q._entity._driver:execute(sql, bindings)[1].count or 0
end

function Query:sum(column)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { "SUM(" .. Quoting.quoteIdentifier(column) .. ") as sum" }
    local sql, bindings = q:toSQL()
    return q._entity._driver:execute(sql, bindings)[1] and q._entity._driver:execute(sql, bindings)[1].sum or 0
end

function Query:average(column)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { "AVG(" .. Quoting.quoteIdentifier(column) .. ") as avg" }
    local sql, bindings = q:toSQL()
    return q._entity._driver:execute(sql, bindings)[1] and q._entity._driver:execute(sql, bindings)[1].avg or 0
end

function Query:min(column)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { "MIN(" .. Quoting.quoteIdentifier(column) .. ") as min" }
    local sql, bindings = q:toSQL()
    return q._entity._driver:execute(sql, bindings)[1] and q._entity._driver:execute(sql, bindings)[1].min or 0
end

function Query:max(column)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { "MAX(" .. Quoting.quoteIdentifier(column) .. ") as max" }
    local sql, bindings = q:toSQL()
    return q._entity._driver:execute(sql, bindings)[1] and q._entity._driver:execute(sql, bindings)[1].max or 0
end

function Query:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(self, options)
end

function Query:exists()
    local q = Query.new(self._entity)
    q._where = self._where
    q._select = { "1" }
    q._limit = 1
    local sql, bindings = q:toSQL()
    local result = self._entity._driver:execute(sql, bindings)
    return #result > 0
end

function Query:empty()
    return self:count() == 0
end

function Query:pluck(column)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    q._select = { Quoting.quoteIdentifier(column) }
    local sql, bindings = q:toSQL()
    local result = self._entity._driver:execute(sql, bindings)
    local values = {}
    for i, row in ipairs(result) do values[i] = row[column] end
    return values
end

function Query:take(n)
    local q = Query.new(self._entity)
    _copyArrays(self, q); _copyScalars(self, q)
    local random_fn = "RANDOM()"
    local driver = self._entity._driver
    if driver and driver._driver_type == "mysql" then random_fn = "RAND()"
    elseif driver and driver._driver_type == "mariadb" then random_fn = "RAND()" end
    q._orderBy = { { column = random_fn, dir = "" } }
    q._limit = n
    return q:get()
end

function Query:inBatches(batchSize, fn)
    local offset = 0
    while true do
        local q = Query.new(self._entity)
        _copyArrays(self, q); _copyScalars(self, q)
        q._limit = batchSize; q._offset = offset
        local batch = q:get()
        if #batch == 0 then break end
        fn(batch); offset = offset + batchSize
        if #batch < batchSize then break end
    end
end

function Query:as(alias)
    return {
        _query = self,
        _alias = alias,
    }
end

function Query:updateAll(data)
    if not self._where_explicit then
        error("updateAll() requires an explicit .where() filter to prevent accidental full-table update. Use .where(...) before calling .updateAll().")
    end
    local driver = self._entity._driver
    local where = self:_compileWhere()
    local sql, bindings = driver:generateBulkUpdate(self._table, data, where)
    local result = driver:execute(sql, bindings)
    return result
end

function Query:deleteAll()
    if not self._where_explicit then
        error("deleteAll() requires an explicit .where() filter to prevent accidental full-table delete. Use .where(...) before calling .deleteAll().")
    end
    local driver = self._entity._driver
    local where = self:_compileWhere()
    local sql, bindings = driver:generateBulkDelete(self._table, where)
    local result = driver:execute(sql, bindings)
    return result
end

function Query:_compileWhere()
    if #self._where == 0 then
        -- Return a condition that matches all rows (always true)
        return Condition.new("1", "=", 1, "")
    end

    if #self._where == 1 then
        return self._where[1]
    end

    local result = self._where[1]
    for i = 2, #self._where do
        result = result:band(self._where[i])
    end
    return result
end

function Query:toSQL()
    -- Apply soft delete filter WITHOUT mutating self._where permanently
    local SoftDelete = require("jade.entity.soft_delete")
    if not (SoftDelete.isSoftDeleted(self._entity) and not self._include_trashed) then
        local driver = self._entity._driver
        local sql, bindings = driver:generateSelect(self)
        Security.validateQuery(sql, bindings)
        return sql, bindings
    end

    local orig_where = self._where
    self._where = {}
    for i = 1, #orig_where do self._where[i] = orig_where[i] end

    local col = SoftDelete.getSoftDeleteColumn(self._entity)
    if self._only_trashed then
        self._where[#self._where + 1] = Condition.new(col, "IS NOT", nil, self._table)
    else
        self._where[#self._where + 1] = Condition.new(col, "IS", nil, self._table)
    end

    local driver = self._entity._driver
    local sql, bindings = driver:generateSelect(self)
    Security.validateQuery(sql, bindings)
    self._where = orig_where
    return sql, bindings
end

return Query