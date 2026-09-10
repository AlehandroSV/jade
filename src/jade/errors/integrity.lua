local JadeError = require("jade.errors.base")

local IntegrityError = setmetatable({}, { __index = JadeError })
IntegrityError.__index = IntegrityError

function IntegrityError.new(code, message, details)
    local self = JadeError.new(code, message, details)
    setmetatable(self, IntegrityError)
    return self
end

IntegrityError.__tostring = JadeError.tostring

return IntegrityError
