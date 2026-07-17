local Column = {}
Column.__index = Column

function Column.new(_, type_name, length, precision, scale)
    local col = setmetatable({
        type = type_name,
        length = length,
        precision = precision,
        scale = scale,
        _nullable = true,
        _unique = false,
        _primary_key = false,
        _auto_increment = false,
        _default = nil,
        _references = nil,
        _name = nil,
        _table = nil,
    }, Column)
    return col
end

function Column:primaryKey()
    self._primary_key = true
    self._nullable = false
    return self
end

function Column:autoIncrement()
    self._auto_increment = true
    return self
end

function Column:unique()
    self._unique = true
    return self
end

function Column:notNull()
    self._nullable = false
    return self
end

function Column:default(value)
    self._default = value
    return self
end

function Column:defaultNow()
    self._default = "CURRENT_TIMESTAMP"
    return self
end

function Column:references(tbl, column)
    self._references = { table = tbl, column = column or "id" }
    return self
end

function Column:setPrecision(precision, scale)
    self.precision = precision
    self.scale = scale
    return self
end

function Column:clone()
    local copy = setmetatable({}, Column)
    for k, v in pairs(self) do
        copy[k] = v
    end
    return copy
end

return Column
