local JadeError = {}
JadeError.__index = JadeError

function JadeError.new(code, message, details)
    local self = setmetatable({}, JadeError)
    self.code = code
    self.message = message
    self.details = details or {}
    self.timestamp = os.time()
    self.version = require("jade._VERSION")
    return self
end

function JadeError:tostring()
    return string.format("[%s] %s", self.code, self.message)
end

function JadeError:toJSON()
    return {
        code = self.code,
        message = self.message,
        details = self.details,
        timestamp = self.timestamp,
        version = self.version,
    }
end

function JadeError:format(template)
    local result = template
    for key, value in pairs(self.details) do
        result = result:gsub("{" .. key .. "}", tostring(value))
    end
    return result
end

JadeError.__tostring = JadeError.tostring

--- Attach JadeError metamethods to a subclass metatable (Lua does not inherit __tostring via __index).
function JadeError.attach(Class)
    Class.__index = Class
    Class.__tostring = JadeError.tostring
    setmetatable(Class, { __index = JadeError })
    return Class
end

return JadeError

