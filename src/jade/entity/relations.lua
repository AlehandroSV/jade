local Relations = {}

function Relations.ForeignKey(target_entity, options)
    options = options or {}
    local foreign_key = options.foreign_key
    if not foreign_key then
        -- Convention: singularized target table name + _id
        local inflection = require("jade.util.inflection")
        foreign_key = inflection.singularize(target_entity._table) .. "_id"
    end

    return {
        type = "foreign_key",
        target = target_entity,
        foreign_key = foreign_key,
        onDelete = options.onDelete or "CASCADE",
        onUpdate = options.onUpdate or "CASCADE",
    }
end

function Relations.hasMany(source_entity, target_entity, options)
    options = options or {}
    local foreign_key = options.foreign_key
    if not foreign_key then
        local inflection = require("jade.util.inflection")
        foreign_key = inflection.singularize(source_entity._table) .. "_id"
    end

    return {
        type = "hasMany",
        source = source_entity,
        target = target_entity,
        foreign_key = foreign_key,
    }
end

function Relations.hasOne(source_entity, target_entity, options)
    options = options or {}
    local foreign_key = options.foreign_key
    if not foreign_key then
        local inflection = require("jade.util.inflection")
        foreign_key = inflection.singularize(source_entity._table) .. "_id"
    end

    return {
        type = "hasOne",
        source = source_entity,
        target = target_entity,
        foreign_key = foreign_key,
    }
end

function Relations.belongsTo(target_entity, options)
    options = options or {}
    local foreign_key = options.foreign_key
    if not foreign_key then
        local inflection = require("jade.util.inflection")
        foreign_key = inflection.singularize(target_entity._table) .. "_id"
    end

    return {
        type = "belongsTo",
        target = target_entity,
        foreign_key = foreign_key,
    }
end

function Relations.hasAndBelongsToMany(source_entity, target_entity, options)
    options = options or {}
    local inflection = require("jade.util.inflection")

    local join_table = options.join_table
    if not join_table then
        -- Convention: alphabetical order of table names
        local tables = { source_entity._table, target_entity._table }
        table.sort(tables)
        join_table = tables[1] .. "_" .. tables[2]
    end

    local source_key = options.source_key or "id"
    local target_key = options.target_key or "id"
    local source_foreign_key = options.source_foreign_key or (inflection.singularize(source_entity._table) .. "_id")
    local target_foreign_key = options.target_foreign_key or (inflection.singularize(target_entity._table) .. "_id")

    return {
        type = "hasAndBelongsToMany",
        source = source_entity,
        target = target_entity,
        join_table = join_table,
        source_key = source_key,
        target_key = target_key,
        source_foreign_key = source_foreign_key,
        target_foreign_key = target_foreign_key,
    }
end

function Relations.hasManyThrough(source_entity, target_entity, through_entity, options)
    options = options or {}
    local inflection = require("jade.util.inflection")

    local source_foreign_key = options.source_foreign_key or (inflection.singularize(source_entity._table) .. "_id")
    local target_foreign_key = options.target_foreign_key or (inflection.singularize(target_entity._table) .. "_id")

    return {
        type = "hasManyThrough",
        source = source_entity,
        target = target_entity,
        through = through_entity,
        source_foreign_key = source_foreign_key,
        target_foreign_key = target_foreign_key,
    }
end

return Relations