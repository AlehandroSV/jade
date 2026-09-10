local JadeError = require("jade.errors.base")

local QueryError = setmetatable({}, { __index = JadeError })
QueryError.__index = QueryError

function QueryError.new(code, message, details)
    local self = JadeError.new(code, message, details)
    setmetatable(self, QueryError)
    return self
end

QueryError.__tostring = JadeError.tostring

return QueryError
