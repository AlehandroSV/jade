--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief Column base class with fluent API

--- @class Jade.Column
--- @field type string Column type identifier
--- @field length? number Maximum length for string types
--- @field precision? number Decimal precision
--- @field scale? number Decimal scale
--- @field _nullable boolean Whether this column allows NULL
--- @field _unique boolean Whether this column has UNIQUE constraint
--- @field _primary_key boolean Whether this is a primary key
--- @field _auto_increment boolean Whether this column auto-increments
--- @field _default any Default value
--- @field _references? {table: string, column: string} Foreign key reference
--- @field _name? string Column name
--- @field _table? string Table name
--- @field _encrypted boolean Whether this column is encrypted
--- @field _enum_values? string[] Enum allowed values
local Column = {}
Column.__index = Column

--- Create a new Column instance
--- @param _ any Unused self parameter
--- @param type_name string Column type identifier
--- @param length? number Maximum length
--- @param precision? number Decimal precision
--- @param scale? number Decimal scale
--- @return Jade.Column New column instance
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

--- Set this column as primary key (also sets NOT NULL)
--- @return Jade.Column self
function Column:primaryKey()
    self._primary_key = true
    self._nullable = false
    return self
end

--- Set this column to auto-increment
--- @return Jade.Column self
function Column:autoIncrement()
    self._auto_increment = true
    return self
end

--- Set this column as unique
--- @return Jade.Column self
function Column:unique()
    self._unique = true
    return self
end

--- Set this column as NOT NULL
--- @return Jade.Column self
function Column:notNull()
    self._nullable = false
    return self
end

--- Set a default value for this column
--- @param value any Default value
--- @return Jade.Column self
function Column:default(value)
    self._default = value
    return self
end

--- Set default value to CURRENT_TIMESTAMP
--- @return Jade.Column self
function Column:defaultNow()
    self._default = "CURRENT_TIMESTAMP"
    return self
end

--- Add a foreign key reference
--- @param tbl string Target table name
--- @param column? string Target column name (default: "id")
--- @return Jade.Column self
function Column:references(tbl, column)
    self._references = { table = tbl, column = column or "id" }
    return self
end

--- Set precision and scale for decimal types
--- @param precision number Total digits
--- @param scale number Decimal places
--- @return Jade.Column self
function Column:setPrecision(precision, scale)
    self.precision = precision
    self.scale = scale
    return self
end

--- Create a copy of this column
--- @return Jade.Column Cloned column
function Column:clone()
    local copy = setmetatable({}, Column)
    for k, v in pairs(self) do
        copy[k] = v
    end
    return copy
end

--- Mark this column as encrypted
--- @return Jade.Column self
function Column:encrypted()
    self._encrypted = true
    return self
end

return Column
