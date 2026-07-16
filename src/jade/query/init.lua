local Expression = require("jade.query.expression")
local Condition = require("jade.query.condition")
local Instance = require("jade.entity.instance")

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
    }, Query)
end

function Query:where(condition)
    self._where[#self._where + 1] = condition
    return self
end

function Query:orderBy(column, direction)
    local col_name = column
    local dir = direction or "ASC"

    if type(column) == "table" and column._column then
        col_name = column._column
    end

    self._orderBy[#self._orderBy + 1] = { column = col_name, dir = dir }
    return self
end

function Query:limit(n)
    self._limit = n
    return self
end

function Query:offset(n)
    self._offset = n
    return self
end

function Query:select(...)
    local cols = { ... }
    if #cols == 1 and type(cols[1]) == "table" then
        cols = cols[1]
    end
    for _, col in ipairs(cols) do
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
    self._joins[#self._joins + 1] = { type = "INNER", table = table_name, on = on_condition }
    return self
end

function Query:leftJoin(table_name, on_condition)
    self._joins[#self._joins + 1] = { type = "LEFT", table = table_name, on = on_condition }
    return self
end

function Query:rightJoin(table_name, on_condition)
    self._joins[#self._joins + 1] = { type = "RIGHT", table = table_name, on = on_condition }
    return self
end

function Query:innerJoin(table_name, on_condition)
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

function Query:get()
    local sql, bindings = self:toSQL()
    local driver = self._entity._driver
    local raw = driver:execute(sql, bindings)
    local instances = {}
    for i, row in ipairs(raw) do
        instances[i] = Instance.new(self._entity, row)
    end

    -- Eager load included relations
    if #self._includes > 0 then
        self:_eagerLoad(instances)
    end

    return instances
end

function Query:_eagerLoad(instances)
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
                        relation.source_foreign_key,
                        relation.target_foreign_key,
                        relation.join_table,
                        relation.source_foreign_key,
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
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = self._select
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = 1
    q._offset = self._offset
    local results = q:get()
    return results[1]
end

function Query:find(id)
    local q = Query.new(self._entity)
    q._where = { Condition.new("id", "=", id, self._table) }
    q._orderBy = self._orderBy
    q._select = self._select
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = 1
    q._offset = self._offset
    local results = q:get()
    return results[1]
end

function Query:count()
    local q = Query.new(self._entity)
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = { "COUNT(*) as count" }
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = self._limit
    q._offset = self._offset
    local sql, bindings = q:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].count or 0
end

function Query:sum(column)
    local q = Query.new(self._entity)
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = { "SUM(" .. column .. ") as sum" }
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = self._limit
    q._offset = self._offset
    local sql, bindings = q:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].sum or 0
end

function Query:average(column)
    local q = Query.new(self._entity)
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = { "AVG(" .. column .. ") as avg" }
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = self._limit
    q._offset = self._offset
    local sql, bindings = q:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].avg or 0
end

function Query:min(column)
    local q = Query.new(self._entity)
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = { "MIN(" .. column .. ") as min" }
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = self._limit
    q._offset = self._offset
    local sql, bindings = q:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].min or 0
end

function Query:max(column)
    local q = Query.new(self._entity)
    q._where = self._where
    q._orderBy = self._orderBy
    q._select = { "MAX(" .. column .. ") as max" }
    q._includes = self._includes
    q._joins = self._joins
    q._groupBy = self._groupBy
    q._having = self._having
    q._distinct = self._distinct
    q._limit = self._limit
    q._offset = self._offset
    local sql, bindings = q:toSQL()
    local driver = self._entity._driver
    local result = driver:execute(sql, bindings)
    return result[1] and result[1].max or 0
end

function Query:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(self, options)
end

function Query:toSQL()
    local driver = self._entity._driver
    return driver:generateSelect(self)
end

return Query