describe("Transaction", function()
    local Transaction = require("jade.transaction")
    local TransactionManager = require("jade.transaction.manager")

    -- Mock driver
    local mock_driver
    local connection_mock

    before_each(function()
        connection_mock = {
            id = 1,
        }
        mock_driver = {
            getConnection = function(self)
                return connection_mock
            end,
            beginTransaction = function(self, conn)
                conn._in_tx = true
            end,
            commitTransaction = function(self, conn)
                conn._in_tx = false
            end,
            rollbackTransaction = function(self, conn)
                conn._in_tx = false
            end,
            executeWithConnection = function(self, conn, sql, bindings)
                return { { result = "ok" } }
            end,
        }
    end)

    describe("Transaction", function()
        it("creates a transaction", function()
            local tx = Transaction.new(mock_driver)
            assert.is_false(tx:isActive())
        end)

        it("starts a transaction", function()
            local tx = Transaction.new(mock_driver)
            tx:start()
            assert.is_true(tx:isActive())
        end)

        it("commits a transaction", function()
            local tx = Transaction.new(mock_driver)
            tx:start()
            tx:commit()
            assert.is_false(tx:isActive())
        end)

        it("rolls back a transaction", function()
            local tx = Transaction.new(mock_driver)
            tx:start()
            tx:rollback()
            assert.is_false(tx:isActive())
        end)

        it("executes SQL within transaction", function()
            local tx = Transaction.new(mock_driver)
            tx:start()
            local result = tx:execute("SELECT 1")
            assert.is_not_nil(result)
            tx:commit()
        end)

        it("errors when starting twice", function()
            local tx = Transaction.new(mock_driver)
            tx:start()
            local ok, err = pcall(function()
                tx:start()
            end)
            assert.is_false(ok)
            assert.are.equal("table", type(err))
            assert.are.equal("J4006", err.code)
            assert.is_truthy(tostring(err):match("already active"))
            tx:rollback()
        end)

        it("errors when committing without active", function()
            local tx = Transaction.new(mock_driver)
            local ok, err = pcall(function()
                tx:commit()
            end)
            assert.is_false(ok)
            assert.are.equal("table", type(err))
            assert.are.equal("J4006", err.code)
            assert.is_truthy(tostring(err):match("No active transaction"))
        end)

        it("errors when rolling back without active", function()
            local tx = Transaction.new(mock_driver)
            local ok, err = pcall(function()
                tx:rollback()
            end)
            assert.is_false(ok)
            assert.are.equal("table", type(err))
            assert.are.equal("J4006", err.code)
            assert.is_truthy(tostring(err):match("No active transaction"))
        end)
    end)

    describe("Transaction Manager", function()
        it("runs function in transaction", function()
            local committed = false
            mock_driver.commitTransaction = function(self, conn)
                conn._in_tx = false
                committed = true
            end

            TransactionManager.run(mock_driver, function(tx)
                tx:execute("SELECT 1")
            end)
            assert.is_true(committed)
        end)

        it("rolls back on error", function()
            local rolled_back = false
            mock_driver.rollbackTransaction = function(self, conn)
                conn._in_tx = false
                rolled_back = true
            end

            local ok = pcall(function()
                TransactionManager.run(mock_driver, function(tx)
                    error("test error")
                end)
            end)
            assert.is_false(ok)
            assert.is_true(rolled_back)
        end)
    end)
end)
