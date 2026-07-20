local Column = require("jade.schema.column")

local BigInt = {}
BigInt.__index = BigInt

setmetatable(BigInt, {
    __index = Column,
    __call = function(_)
        return Column.new(nil, "bigint")
    end,
})

return BigInt
