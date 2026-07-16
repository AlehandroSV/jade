local Validations = {}

function Validations.setup(entity)
    entity._validations = {}

    -- Add validation methods to entity
    function entity:validate(data)
        return Validations.validate(self, data)
    end

    function entity:validatePresenceOf(column)
        Validations.presenceOf(self, column)
    end

    function entity:validateUniquenessOf(column, options)
        Validations.uniquenessOf(self, column, options)
    end

    function entity:validateLengthOf(column, options)
        Validations.lengthOf(self, column, options)
    end

    function entity:validateFormatOf(column, options)
        Validations.formatOf(self, column, options)
    end

    function entity:validateInclusionOf(column, options)
        Validations.inclusionOf(self, column, options)
    end

    function entity:validateNumericalityOf(column, options)
        Validations.numericalityOf(self, column, options)
    end

    function entity:validateCustom(column, fn, message)
        Validations.custom(self, column, fn, message)
    end

    return entity
end

function Validations.presenceOf(entity, column)
    table.insert(entity._validations, {
        type = "presence",
        column = column,
    })
end

function Validations.uniquenessOf(entity, column, options)
    options = options or {}
    table.insert(entity._validations, {
        type = "uniqueness",
        column = column,
        scope = options.scope,
        message = options.message,
    })
end

function Validations.lengthOf(entity, column, options)
    options = options or {}
    table.insert(entity._validations, {
        type = "length",
        column = column,
        min = options.min,
        max = options.max,
        is = options.is,
        message = options.message,
    })
end

function Validations.formatOf(entity, column, options)
    options = options or {}
    table.insert(entity._validations, {
        type = "format",
        column = column,
        pattern = options.pattern,
        message = options.message,
    })
end

function Validations.inclusionOf(entity, column, options)
    options = options or {}
    table.insert(entity._validations, {
        type = "inclusion",
        column = column,
        values = options.values,
        message = options.message,
    })
end

function Validations.numericalityOf(entity, column, options)
    options = options or {}
    table.insert(entity._validations, {
        type = "numericality",
        column = column,
        integer_only = options.integer_only,
        message = options.message,
    })
end

function Validations.custom(entity, column, fn, message)
    table.insert(entity._validations, {
        type = "custom",
        column = column,
        fn = fn,
        message = message or "is invalid",
    })
end

function Validations.validate(entity, data)
    local errors = {}
    local Expression = require("jade.query.expression")
    local Condition = require("jade.query.condition")
    local Query = require("jade.query")

    for _, validation in ipairs(entity._validations) do
        local value = data[validation.column]
        local valid = true
        local message = nil

        if validation.type == "presence" then
            if value == nil or value == "" then
                valid = false
                message = validation.column .. " is required"
            end

        elseif validation.type == "uniqueness" then
            if value ~= nil and entity._driver then
                local q = Query.new(entity)
                local conditions = { Condition.new(validation.column, "=", value, entity._table) }

                -- Add scope conditions if provided
                if validation.scope then
                    local scope_columns = validation.scope
                    if type(scope_columns) == "string" then
                        scope_columns = { scope_columns }
                    end
                    for _, scope_col in ipairs(scope_columns) do
                        local scope_value = data[scope_col]
                        if scope_value ~= nil then
                            conditions[#conditions + 1] = Condition.new(scope_col, "=", scope_value, entity._table)
                        end
                    end
                end

                -- Build WHERE clause with AND
                local where = conditions[1]
                for i = 2, #conditions do
                    where = where:band(conditions[i])
                end

                q._where = { where }
                q._limit = 1
                local sql, bindings = q:toSQL()
                local result = entity._driver:execute(sql, bindings)
                if #result > 0 then
                    -- Check if it's the same record (for updates)
                    local existing_id = result[1].id
                    local current_id = data.id
                    -- Use tostring for safe comparison (handles number/string mismatch)
                    if not current_id or tostring(existing_id) ~= tostring(current_id) then
                        valid = false
                        message = validation.message or (validation.column .. " already exists")
                    end
                end
            end

        elseif validation.type == "length" then
            if value ~= nil and type(value) == "string" then
                local len = #value
                if validation.is and len ~= validation.is then
                    valid = false
                    message = validation.message or (validation.column .. " must be exactly " .. validation.is .. " characters")
                elseif validation.min and len < validation.min then
                    valid = false
                    message = validation.message or (validation.column .. " must be at least " .. validation.min .. " characters")
                elseif validation.max and len > validation.max then
                    valid = false
                    message = validation.message or (validation.column .. " must be at most " .. validation.max .. " characters")
                end
            end

        elseif validation.type == "format" then
            if value ~= nil and type(value) == "string" then
                if not value:match(validation.pattern) then
                    valid = false
                    message = validation.message or (validation.column .. " is invalid format")
                end
            end

        elseif validation.type == "inclusion" then
            if value ~= nil then
                local found = false
                for _, v in ipairs(validation.values) do
                    if v == value then
                        found = true
                        break
                    end
                end
                if not found then
                    valid = false
                    message = validation.message or (validation.column .. " is not included in the list")
                end
            end

        elseif validation.type == "numericality" then
            if value ~= nil then
                if type(value) ~= "number" then
                    valid = false
                    message = validation.message or (validation.column .. " is not a number")
                elseif validation.integer_only and value ~= math.floor(value) then
                    valid = false
                    message = validation.message or (validation.column .. " must be an integer")
                end
            end

        elseif validation.type == "custom" then
            if value ~= nil then
                local ok, err = pcall(validation.fn, value, data)
                if not ok or err == false then
                    valid = false
                    message = validation.message or (validation.column .. " is invalid")
                end
            end
        end

        if not valid then
            errors[#errors + 1] = message
        end
    end

    if #errors > 0 then
        return errors
    end
    return nil
end

return Validations