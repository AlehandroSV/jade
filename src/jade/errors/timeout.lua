local JadeError = require("jade.errors.base")

local QueryTimeoutError = setmetatable({}, { __index = JadeError })
QueryTimeoutError.__index = QueryTimeoutError

function QueryTimeoutError.new(timeout_ms, sql)
    local message = string.format("Query exceeded timeout of %dms", timeout_ms)
    local details = {
        timeout_ms = timeout_ms,
        sql = sql,
    }
    local self = JadeError.new("QUERY_TIMEOUT", message, details)
    setmetatable(self, QueryTimeoutError)
    return self
end

return QueryTimeoutError
