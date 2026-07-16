local Callbacks = {}

function Callbacks.setup(entity)
    entity._callbacks = {
        before_create = {},
        after_create = {},
        before_update = {},
        after_update = {},
        before_delete = {},
        after_delete = {},
        before_save = {},
        after_save = {},
        around_create = {},
        around_update = {},
        around_delete = {},
        around_save = {},
    }

    -- Add callback registration methods to entity
    function entity:beforeCreate(fn)
        table.insert(self._callbacks.before_create, fn)
    end

    function entity:afterCreate(fn)
        table.insert(self._callbacks.after_create, fn)
    end

    function entity:beforeUpdate(fn)
        table.insert(self._callbacks.before_update, fn)
    end

    function entity:afterUpdate(fn)
        table.insert(self._callbacks.after_update, fn)
    end

    function entity:beforeDelete(fn)
        table.insert(self._callbacks.before_delete, fn)
    end

    function entity:afterDelete(fn)
        table.insert(self._callbacks.after_delete, fn)
    end

    function entity:beforeSave(fn)
        table.insert(self._callbacks.before_save, fn)
    end

    function entity:afterSave(fn)
        table.insert(self._callbacks.after_save, fn)
    end

    function entity:aroundCreate(fn)
        table.insert(self._callbacks.around_create, fn)
    end

    function entity:aroundUpdate(fn)
        table.insert(self._callbacks.around_update, fn)
    end

    function entity:aroundDelete(fn)
        table.insert(self._callbacks.around_delete, fn)
    end

    function entity:aroundSave(fn)
        table.insert(self._callbacks.around_save, fn)
    end

    return entity
end

function Callbacks.run(entity, event, instance, data)
    local hooks = entity._callbacks[event]
    if not hooks then return end

    for _, fn in ipairs(hooks) do
        local ok, err = pcall(fn, instance, data)
        if not ok then
            error("Callback error (" .. event .. "): " .. tostring(err))
        end
    end
end

function Callbacks.runAround(entity, event, instance, data, fn)
    local hooks = entity._callbacks[event]
    if not hooks or #hooks == 0 then
        return fn()
    end

    -- Chain around callbacks
    local function execute_chain(idx)
        if idx > #hooks then
            return fn()
        end
        return hooks[idx](instance, data, function()
            return execute_chain(idx + 1)
        end)
    end

    return execute_chain(1)
end

return Callbacks