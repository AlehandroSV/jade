--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief String column type definition

local Column = require("jade.schema.column")

--- @class Jade.StringColumn : Jade.Column
--- @field _type string Column type identifier
--- @field _length number Maximum string length
local String = {}
String.__index = String

setmetatable(String, {
    __index = Column,
    __call = function(_, length)
        return Column.new(nil, "string", length or 255)
    end,
})

return String
