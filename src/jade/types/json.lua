local Column = require("jade.schema.column")

local JSON = {}
JSON.__index = JSON

setmetatable(JSON, {
    __index = Column,
    __call = function(_)
        return Column.new(nil, "json")
    end,
})

return JSON
