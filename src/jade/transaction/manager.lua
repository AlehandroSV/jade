--- @meta declarations for Jade ORM — Lua Language Server type annotations
--- @brief Transaction manager for database operations

--- @class Jade.TransactionManager
local M = {}

local Transaction = require("jade.transaction")

--- Execute a function inside a database transaction
--- @param driver Jade.Driver Database driver
--- @param fn function Function to execute (receives transaction object)
--- @return boolean true if transaction committed successfully
--- @error If function throws, transaction is rolled back
function M.run(driver, fn)
    local tx = Transaction.new(driver)
    tx:start()

    local ok, err = pcall(fn, tx)

    if ok then
        tx:commit()
        return true
    else
        tx:rollback()
        error(err)
    end
end

return M
