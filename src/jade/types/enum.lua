local Column = require("jade.schema.column")

local Enum = {}
Enum.__index = Enum

setmetatable(Enum, {
    __index = Column,
    __call = function(_, values)
        local col = Column.new(nil, "enum")
        col.values = values or {}
        return col
    end,
})

return Enum
