local JadeError = require("jade.errors.base")

local MigrationError = setmetatable({}, { __index = JadeError })
MigrationError.__index = MigrationError

function MigrationError.new(code, message, details)
    local self = JadeError.new(code, message, details)
    setmetatable(self, MigrationError)
    return self
end

MigrationError.__tostring = JadeError.tostring

return MigrationError
