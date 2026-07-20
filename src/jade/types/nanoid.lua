local Column = require("jade.schema.column")

local NanoID = {}
NanoID.__index = NanoID

setmetatable(NanoID, {
    __index = Column,
    __call = function(_)
        local col = Column.new(nil, "nanoid")
        col.length = 21
        return col
    end,
})

return NanoID
