local Expression = require("jade.query.expression")
local Query = require("jade.query")
local Instance = require("jade.entity.instance")
local Relations = require("jade.entity.relations")
local Validations = require("jade.entity.validations")
local Callbacks = require("jade.entity.callbacks")
local Events = require("jade.entity.events")
local Security = require("jade.security")

local Entity = {}
Entity.__index = function(self, key)
    -- Check if key is a method
    local method = rawget(Entity, key)
    if method then
        return method
    end

    -- Check if key is a relation -> return lazy proxy
    if self._relations and self._relations[key] then
        local Proxy = require("jade.entity.proxy")
        return Proxy.new(self._relations[key], self._owner or self)
    end

    -- Check if key is a column name -> return Expression
    if self._columns and self._columns[key] then
        return Expression.new(key, self._table)
    end

    return nil
end

function Entity.new(table_name, columns, options)
    options = options or {}
    local model = setmetatable({
        _table = table_name,
        _columns = columns,
        _relations = {},
        _driver = nil,
        _database = options.database or nil,
        _validations = {},
        _callbacks = {},
        _scopes = {},
    }, Entity)

    -- Register column names and encrypted markers
    local Encryption = require("jade.encryption")
    for name, col in pairs(columns) do
        col._name = name
        col._table = table_name
        if col._encrypted then
            Encryption.markColumn(table_name, name)
        end
    end

    -- Setup validations and callbacks
    Validations.setup(model)
    Callbacks.setup(model)

    -- Auto-connect to assigned database if available
    if model._database then
        local Database = require("jade.database")
        local ok, driver = pcall(Database.connect, model._database)
        if ok then
            model:configure(driver)
        end
    end

    return model
end

function Entity:configure(driver)
    self._driver = driver
end

function Entity:scope(name, ...)
    local args = { ... }
    if #args > 0 and type(args[1]) == "function" then
        -- Define scope
        self._scopes[name] = args[1]
        return self
    else
        -- Invoke scope
        local scope_fn = self._scopes[name]
        if scope_fn then
            local q = Query.new(self)
            return scope_fn(q, table.unpack(args))
        end
        return Query.new(self)
    end
end

-- Helper: derive relation key from entity
local function entityRelKey(target)
    local inflection = require("jade.util.inflection")
    local singular = inflection.singularize(target._table)
    return target._table, singular
end

-- Relation definitions
function Entity:belongsTo(target_entity, options)
    local relation = Relations.belongsTo(target_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then
        self._relations[entityName] = relation
    end
    return self
end

function Entity:hasOne(target_entity, options)
    local relation = Relations.hasOne(self, target_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then self._relations[entityName] = relation end
    return self
end

function Entity:hasMany(target_entity, options)
    local relation = Relations.hasMany(self, target_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then self._relations[entityName] = relation end
    return self
end

function Entity:foreignKey(target_entity, options)
    local relation = Relations.ForeignKey(target_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then self._relations[entityName] = relation end
    return self
end

function Entity:hasAndBelongsToMany(target_entity, options)
    local relation = Relations.hasAndBelongsToMany(self, target_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then self._relations[entityName] = relation end
    return self
end

function Entity:hasManyThrough(target_entity, through_entity, options)
    local relation = Relations.hasManyThrough(self, target_entity, through_entity, options)
    local tableName, entityName = entityRelKey(target_entity)
    self._relations[tableName] = relation
    if entityName ~= tableName then self._relations[entityName] = relation end
    return self
end

-- Query methods
function Entity:where(condition)
    return Query.new(self):where(condition)
end

function Entity:orderBy(column, direction)
    return Query.new(self):orderBy(column, direction)
end

function Entity:limit(n)
    return Query.new(self):limit(n)
end

function Entity:offset(n)
    return Query.new(self):offset(n)
end

function Entity:select(...)
    return Query.new(self):select(...)
end

function Entity:include(relation_name)
    return Query.new(self):include(relation_name)
end

function Entity:distinct()
    return Query.new(self):distinct()
end

function Entity:join(table_name, on_condition)
    return Query.new(self):join(table_name, on_condition)
end

function Entity:leftJoin(table_name, on_condition)
    return Query.new(self):leftJoin(table_name, on_condition)
end

function Entity:groupBy(...)
    return Query.new(self):groupBy(...)
end

function Entity:having(condition)
    return Query.new(self):having(condition)
end

function Entity:get()
    return Query.new(self):get()
end

function Entity:first()
    return Query.new(self):first()
end

-- find(id) - find by primary key (backward compatible)
-- find({ where = {...}, orderBy = {...} }) - find multiple with options
function Entity:find(id_or_options)
    if type(id_or_options) == "table" then
        -- Flexible find with options
        local options = id_or_options
        local q = Query.new(self)
        if options.where then
            local Condition = require("jade.query.condition")
            for k, v in pairs(options.where) do
                q = q:where(Condition.new(k, "=", v, self._table))
            end
        end
        if options.orderBy then
            for col, dir in pairs(options.orderBy) do
                q = q:orderBy(col, dir)
            end
        end
        if options.limit then
            q = q:limit(options.limit)
        end
        if options.offset then
            q = q:offset(options.offset)
        end
        return q:get()
    else
        -- Find by ID (original behavior)
        return Query.new(self):find(id_or_options)
    end
end

-- Flexible query methods

-- findFirst({ where = { col = val } }) - find first matching record
function Entity:findFirst(options)
    local q = Query.new(self)
    if options and options.where then
        local Condition = require("jade.query.condition")
        for k, v in pairs(options.where) do
            q = q:where(Condition.new(k, "=", v, self._table))
        end
    end
    if options and options.orderBy then
        for col, dir in pairs(options.orderBy) do
            q = q:orderBy(col, dir)
        end
    end
    return q:first()
end

-- findFirstOrThrow({ where = { col = val } }) - find first or error
function Entity:findFirstOrThrow(options)
    local result = self:findFirst(options)
    if not result then
        error("No " .. self._table .. " found with given conditions")
    end
    return result
end

-- findUnique({ where = { email = "..." } }) - find by unique field
function Entity:findUnique(options)
    if not options or not options.where then
        error("findUnique requires a where clause")
    end
    return self:findFirst(options)
end

-- findUniqueOrThrow({ where = { email = "..." } }) - find unique or error
function Entity:findUniqueOrThrow(options)
    local result = self:findUnique(options)
    if not result then
        error("No " .. self._table .. " found with given unique conditions")
    end
    return result
end

function Entity:count(options)
    local q = Query.new(self)
    if options and options.where then
        local Condition = require("jade.query.condition")
        for k, v in pairs(options.where) do
            q = q:where(Condition.new(k, "=", v, self._table))
        end
    end
    return q:count()
end

function Entity:sum(column)
    return Query.new(self):sum(column)
end

function Entity:average(column)
    return Query.new(self):average(column)
end

function Entity:min(column)
    return Query.new(self):min(column)
end

function Entity:max(column)
    return Query.new(self):max(column)
end

function Entity:paginate(options)
    local paginate = require("jade.query.paginate")
    return paginate.paginate(Query.new(self), options)
end

function Entity:exists(options)
    return self:count(options) > 0
end

function Entity:empty()
    return Query.new(self):empty()
end

function Entity:pluck(column)
    return Query.new(self):pluck(column)
end

function Entity:take(n)
    return Query.new(self):take(n)
end

function Entity:inBatches(batchSize, fn)
    return Query.new(self):inBatches(batchSize, fn)
end

function Entity:updateAll(data)
    return Query.new(self):updateAll(data)
end

function Entity:deleteAll()
    return Query.new(self):deleteAll()
end

function Entity:insertAll(rows)
    if #rows == 0 then
        error("Cannot insert zero rows")
    end
    local sql, bindings = self._driver:generateBulkInsert(self._table, rows, self)
    return self._driver:execute(sql, bindings)
end

function Entity:upsert(data, conflict_columns)
    local sql, bindings = self._driver:generateUpsert(self._table, data, conflict_columns, self)
    return self._driver:execute(sql, bindings)
end

-- Separate data into column values and relation instructions
function Entity:_separateData(data)
    local columns_data = {}
    local relations_data = {}
    for key, value in pairs(data) do
        if self._relations[key] then
            relations_data[key] = value
        elseif self._columns[key] then
            columns_data[key] = value
        end
    end
    return columns_data, relations_data
end

-- Resolve a single relation instruction, return the target record's id
function Entity:_resolveRelation(relName, instruction)
    local rel = self._relations[relName]
    if not rel then error("Relation '" .. relName .. "' not defined") end
    local target = rel.target

    if instruction.connect then
        -- { connect = { id = N } } or { connect = { email = "..." } }
        local record = target:findUnique({ where = instruction.connect })
        if not record then
            error("Cannot connect: no " .. target._table .. " found with " .. require("dkjson").encode(instruction.connect))
        end
        return record._data.id

    elseif instruction.create then
        -- { create = { ... } }
        local record = target:create(instruction.create)
        return record._data.id

    elseif instruction.connectOrCreate then
        -- { connectOrCreate = { where = {...}, create = {...} } }
        local record = target:findUnique({ where = instruction.connectOrCreate.where })
        if not record then
            record = target:create(instruction.connectOrCreate.create)
        end
        return record._data.id

    elseif type(instruction.id) == "number" then
        -- Shorthand: { id = N }
        return instruction.id

    else
        error("Invalid relation instruction for '" .. relName .. "'. Use { connect = {...} }, { create = {...} }, or { connectOrCreate = {...} }")
    end
end

-- Resolve hasMany/hasOne children after parent is created
function Entity:_resolveChildren(relations_data, parentInstance)
    for key, value in pairs(relations_data) do
        local rel = self._relations[key]
        if not rel then goto continue end

        if rel.type == "hasMany" or rel.type == "hasOne" then
            local target = rel.target
            local items = {}

            if value.create then
                -- Single: { create = { ... } }
                items = { value }
            elseif #value > 0 then
                -- Array: { { create = {...} }, { create = {...} } }
                items = value
            end

            for _, item in ipairs(items) do
                if item.create then
                    local child_data = {}
                    for k, v in pairs(item.create) do child_data[k] = v end
                    child_data[rel.foreign_key] = parentInstance._data.id
                    target:create(child_data)
                elseif item.connect then
                    -- Connect existing record (update its FK)
                    local record = target:findUnique({ where = item.connect })
                    if record then
                        record:update({ [rel.foreign_key] = parentInstance._data.id })
                    end
                end
            end

        elseif rel.type == "hasAndBelongsToMany" then
            local driver = self._driver
            if value.connect then
                local ids = {}
                if value.connect.ids then
                    ids = value.connect.ids
                elseif value.connect.id then
                    ids = { value.connect.id }
                end
                for _, target_id in ipairs(ids) do
                    driver:execute(
                        string.format("INSERT INTO %s (%s, %s) VALUES ($1, $2)",
                            rel.join_table, rel.source_foreign_key, rel.target_foreign_key),
                        { parentInstance._data.id, target_id }
                    )
                end
            end
        end

        ::continue::
    end
end

-- CRUD with validation and callbacks
function Entity:create(data)
    -- Separate columns from relations
    local columns_data, relations_data = self:_separateData(data)

    -- Resolve belongsTo FIRST (need FK for main insert)
    for key, value in pairs(relations_data) do
        local rel = self._relations[key]
        if rel and rel.type == "belongsTo" then
            local fk_value = self:_resolveRelation(key, value)
            columns_data[rel.foreign_key] = fk_value
        end
    end

    -- Validate input data for SQL injection and type safety
    Security.validateInput(columns_data, self._columns)

    -- Run validations on columns only
    local errors = self:validate(columns_data)
    if errors then
        error("Validation failed: " .. table.concat(errors, ", "))
    end

    -- Run around callbacks
    local result = Callbacks.runAround(self, "around_save", nil, columns_data, function()
        Callbacks.run(self, "before_save", nil, columns_data)
        Callbacks.run(self, "before_create", nil, columns_data)

        -- Prepare data with encryption markers
        local Encryption = require("jade.encryption")
        local enc_data, encrypt_cols = Encryption.prepareInsert(columns_data, self._table, self._columns, self._driver)
        self._encrypt_cols = encrypt_cols

        local sql, bindings = self._driver:generateInsert(self._table, enc_data, self)
        local result = self._driver:execute(sql, bindings)
        local row = result[1] or result

        -- Clear encryption markers
        self._encrypt_cols = nil

        local instance = Instance.new(self, row)

        -- Resolve hasMany/hasOne/hasAndBelongsToMany AFTER parent is created
        self:_resolveChildren(relations_data, instance)

        Callbacks.run(self, "after_create", instance, data)
        Callbacks.run(self, "after_save", instance, data)

        -- Fire built-in event
        Events.fire(self, "created", { instance = instance, data = data })

        return instance
    end)

    return result
end

-- update(id, data) - update by ID
-- update({ where = {...}, data = {...} }) - update with conditions
function Entity:update(id_or_options, data)
    if type(id_or_options) == "table" then
        -- Update with conditions
        local options = id_or_options
        local q = Query.new(self)
        if options.where then
            local Condition = require("jade.query.condition")
            for k, v in pairs(options.where) do
                q = q:where(Condition.new(k, "=", v, self._table))
            end
        end
        return q:updateAll(options.data)
    else
        -- Update by ID (original behavior)
        local id = id_or_options

        -- Separate columns from relations
        local columns_data, relations_data = self:_separateData(data)

        -- Resolve belongsTo FIRST
        for key, value in pairs(relations_data) do
            local rel = self._relations[key]
            if rel and rel.type == "belongsTo" then
                local fk_value = self:_resolveRelation(key, value)
                columns_data[rel.foreign_key] = fk_value
            end
        end

        -- Validate input data for SQL injection and type safety
        Security.validateInput(columns_data, self._columns)

        -- Copy data to avoid mutating caller's table
        local update_data = {}
        for k, v in pairs(columns_data) do update_data[k] = v end
        update_data.id = id

        -- Run validations
        local errors = self:validate(update_data)
        if errors then
            error("Validation failed: " .. table.concat(errors, ", "))
        end

        -- Run around callbacks
        local result = Callbacks.runAround(self, "around_save", nil, update_data, function()
            Callbacks.run(self, "before_save", nil, update_data)
            Callbacks.run(self, "before_update", nil, update_data)

            local Condition = require("jade.query.condition")
            local where = Condition.new("id", "=", id, self._table)

            -- Prepare data with encryption markers
            local Encryption = require("jade.encryption")
            local enc_data, encrypt_cols = Encryption.prepareUpdate(update_data, self._table, self._columns, self._driver)
            self._encrypt_cols = encrypt_cols

            local sql, bindings = self._driver:generateUpdate(self._table, enc_data, where, self)
            local result = self._driver:execute(sql, bindings)
            local row = result[1] or result

            -- Clear encryption markers
            self._encrypt_cols = nil

            local instance = Instance.new(self, row)

            -- Resolve hasMany/hasOne/hasAndBelongsToMany AFTER update
            self:_resolveChildren(relations_data, instance)

            Callbacks.run(self, "after_update", instance, update_data)
            Callbacks.run(self, "after_save", instance, update_data)

            -- Fire built-in event
            Events.fire(self, "updated", { instance = instance, data = update_data })

            return instance
        end)

        return result
    end
end

-- delete(id) - delete by ID
-- delete({ where = {...} }) - delete with conditions
function Entity:delete(id_or_options)
    if type(id_or_options) == "table" then
        -- Delete with conditions
        local options = id_or_options
        local q = Query.new(self)
        if options.where then
            local Condition = require("jade.query.condition")
            for k, v in pairs(options.where) do
                q = q:where(Condition.new(k, "=", v, self._table))
            end
        end
        return q:deleteAll()
    else
        -- Delete by ID (original behavior)
        local id = id_or_options

        -- Run callbacks
        Callbacks.run(self, "before_delete", nil, { id = id })

        local Condition = require("jade.query.condition")
        local where = Condition.new("id", "=", id, self._table)
        local sql, bindings = self._driver:generateDelete(self._table, where)
        local result = self._driver:execute(sql, bindings)
        local row = result[1] or result
        local instance = Instance.new(self, row)

        Callbacks.run(self, "after_delete", instance, { id = id })

        -- Fire built-in event
        Events.fire(self, "deleted", { instance = instance, data = { id = id } })

        return instance
    end
end

-- Events
function Entity:events(names)
    Events.define(self, names)
    return self
end

function Entity:fire(name, data)
    Events.fire(self, name, data)
    return self
end

-- Optimistic Locking
function Entity:optimisticLocking(options)
    options = options or {}
    local column = options.column or "version"

    -- Add version column to entity
    local Integer = require("jade.types.integer")
    self._columns[column] = Integer():default(1)
    self._columns[column]._name = column
    self._columns[column]._table = self._table

    -- Store config
    self._optimistic_locking = { column = column }

    -- Override update to include version check
    local original_update = self.update
    self.update = function(self, id, data)
        -- Copy data to avoid mutating caller's table
        local update_data = {}
        for k, v in pairs(data) do update_data[k] = v end

        -- Add version condition if not already set
        local Condition = require("jade.query.condition")
        if update_data[column] == nil then
            -- Get current version from database
            local current = self:find(id)
            if current and current._data[column] ~= nil then
                update_data[column] = current._data[column]
            end
        end

        local version_value = update_data[column]
        update_data[column] = (version_value or 0) + 1

        -- Run the original update with version in data
        local result = original_update(self, id, update_data)

        -- Check if update affected any rows (conflict detection)
        if result == nil then
            return nil
        end

        return result
    end

    return self
end

return Entity
