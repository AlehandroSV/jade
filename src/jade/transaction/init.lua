local errors = require("jade.errors")

local Transaction = {}
Transaction.__index = Transaction

function Transaction.new(driver)
    return setmetatable({
        _driver = driver,
        _active = false,
        _conn = nil,
    }, Transaction)
end

function Transaction:start()
    if self._active then
        errors.raise(errors.TRANSACTION_FAILED, {
            error = "Transaction already active",
        }, 2)
    end
    self._conn = self._driver:getConnection()
    self._driver:beginTransaction(self._conn)
    self._active = true
    return self
end

function Transaction:commit()
    if not self._active then
        errors.raise(errors.TRANSACTION_FAILED, {
            error = "No active transaction",
        }, 2)
    end
    self._driver:commitTransaction(self._conn)
    self._active = false
    self._conn = nil
end

function Transaction:rollback()
    if not self._active then
        errors.raise(errors.TRANSACTION_FAILED, {
            error = "No active transaction",
        }, 2)
    end
    self._driver:rollbackTransaction(self._conn)
    self._active = false
    self._conn = nil
end

function Transaction:isActive()
    return self._active
end

function Transaction:getConnection()
    return self._conn
end

function Transaction:execute(sql, bindings)
    if not self._active then
        errors.raise(errors.TRANSACTION_FAILED, {
            error = "No active transaction",
        }, 2)
    end
    return self._driver:executeWithConnection(self._conn, sql, bindings)
end

return Transaction
