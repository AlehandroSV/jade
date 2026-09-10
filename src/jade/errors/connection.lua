local JadeError = require("jade.errors.base")

local ConnectionError = setmetatable({}, { __index = JadeError })
ConnectionError.__index = ConnectionError

function ConnectionError.new(code, message, details)
    local self = JadeError.new(code, message, details)
    setmetatable(self, ConnectionError)
    return self
end

ConnectionError.__tostring = JadeError.tostring

return ConnectionError
