local JadeError = require("jade.errors.base")

local SecurityError = setmetatable({}, { __index = JadeError })
SecurityError.__index = SecurityError

function SecurityError.new(code, message, details)
    local self = JadeError.new(code, message, details)
    setmetatable(self, SecurityError)
    return self
end

SecurityError.__tostring = JadeError.tostring

return SecurityError
