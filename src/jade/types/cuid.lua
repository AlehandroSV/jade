local Column = require("jade.schema.column")

local CUID = {}
CUID.__index = CUID

setmetatable(CUID, {
    __index = Column,
    __call = function(_)
        local col = Column.new(nil, "cuid")
        col.length = 25
        return col
    end,
})

return CUID
