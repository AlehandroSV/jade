describe("Connection Pool", function()
    local Pool = require("jade.driver.pool")

    local function mock_driver()
        local conn_counter = 0
        local driver = {
            connections_created = {},
            connections_closed = {},
            execute_calls = {},
            dead_connections = {},
        }

        function driver:getConnection()
            conn_counter = conn_counter + 1
            local conn = { id = conn_counter }
            table.insert(driver.connections_created, conn)
            return conn
        end

        function driver:executeWithConnection(conn, sql, bindings)
            if driver.dead_connections[conn.id] then
                return nil
            end
            table.insert(driver.execute_calls, { conn = conn, sql = sql, bindings = bindings })
            return { rows = {}, affected = 1 }
        end

        function driver:closeConnection(conn)
            table.insert(driver.connections_closed, conn)
        end

        function driver:disconnect(conn)
            table.insert(driver.connections_closed, conn)
        end

        function driver:mark_dead(conn)
            driver.dead_connections[conn.id] = true
        end

        return driver
    end

    describe("Pool.new", function()
        it("pre-creates min_size connections", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 3 })

            assert.are.equal(3, #pool.connections)
            assert.are.equal(3, pool.created)
        end)

        it("defaults min_size to 2", function()
            local driver = mock_driver()
            local pool = Pool.new(driver)

            assert.are.equal(2, #pool.connections)
        end)

        it("initializes abandoned_timeout from options", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { abandoned_timeout = 120 })

            assert.are.equal(120, pool.abandoned_timeout)
        end)

        it("defaults abandoned_timeout to 60", function()
            local driver = mock_driver()
            local pool = Pool.new(driver)

            assert.are.equal(60, pool.abandoned_timeout)
        end)
    end)

    describe("acquire / release", function()
        it("returns an idle connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2 })

            local conn = pool:acquire()
            assert.is_truthy(conn)
            assert.are.equal(1, pool.checked_out)
        end)

        it("reuses released connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local conn1 = pool:acquire()
            pool:release(conn1)
            local conn2 = pool:acquire()

            assert.are.equal(conn1, conn2)
        end)

        it("creates new connection when all are in use", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 2 })

            local conn1 = pool:acquire()
            local conn2 = pool:acquire()

            assert.is_true(conn1 ~= conn2)
            assert.are.equal(2, pool.created)
        end)

        it("errors when pool is exhausted", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1 })

            pool:acquire()

            assert.has_error(function()
                pool:acquire()
            end)
        end)
    end)

    describe("withConnection", function()
        it("executes function and returns result", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local result = pool:withConnection(function(conn)
                return driver:executeWithConnection(conn, "SELECT 1")
            end)

            assert.is_truthy(result)
            assert.are.equal(0, pool.checked_out)
        end)

        it("releases connection when function succeeds", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            pool:withConnection(function(conn)
                return "ok"
            end)

            assert.are.equal(0, pool.checked_out)
            assert.is_false(pool.connections[1].in_use)
        end)

        it("releases connection when function throws error", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            assert.has_error(function()
                pool:withConnection(function(conn)
                    error("boom")
                end)
            end)

            assert.are.equal(0, pool.checked_out)
            assert.is_false(pool.connections[1].in_use)
        end)

        it("releases connection even when error occurs mid-operation", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1 })

            assert.has_error(function()
                pool:withConnection(function(conn)
                    local x = nil
                    x.foo = 1
                end)
            end)

            assert.are.equal(0, pool.checked_out)

            local conn = pool:acquire()
            assert.is_truthy(conn)
            pool:release(conn)
        end)

        it("propagates error message from inner function", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local ok, err = pcall(function()
                pool:withConnection(function(conn)
                    error("custom error message")
                end)
            end)

            assert.is_false(ok)
            assert.is_truthy(string.find(err, "custom error message"))
        end)

        it("does not leak connections under repeated failures", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1 })

            for i = 1, 10 do
                pcall(function()
                    pool:withConnection(function(conn)
                        error("fail #" .. i)
                    end)
                end)
            end

            assert.are.equal(0, pool.checked_out)
            assert.are.equal(1, pool.created)
        end)
    end)

    describe("abandoned connection detection", function()
        it("does not close abandoned connections during normal cleanup", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, abandoned_timeout = 10 })

            local conn = pool:acquire()
            pool.connections[1].last_used = os.time() - 20

            pool:_cleanIdleConnections()

            assert.are.equal(1, #pool.connections)
            assert.are.equal(1, pool.created)
            assert.are.equal(1, pool.checked_out)
        end)

        it("reclaims abandoned connection when pool is exhausted", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 10 })

            local conn = pool:acquire()
            pool.connections[1].last_used = os.time() - 20
            driver:mark_dead(pool.connections[1].connection)

            local new_conn = pool:acquire()
            assert.is_truthy(new_conn)
            assert.are.equal(1, pool.created)
        end)

        it("reclaims only one abandoned connection at a time", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2, max_size = 2, abandoned_timeout = 10 })

            pool:acquire()
            pool:acquire()

            pool.connections[1].last_used = os.time() - 20
            pool.connections[2].last_used = os.time() - 20
            driver:mark_dead(pool.connections[1].connection)
            driver:mark_dead(pool.connections[2].connection)

            local reclaimed = pool:_reclaimOneAbandonedConnection()
            assert.is_true(reclaimed)
            assert.are.equal(1, #pool.connections)
            assert.are.equal(1, pool.created)
            assert.are.equal(1, pool.checked_out)
        end)

        it("does not reclaim connection within abandoned_timeout", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 60 })

            local conn = pool:acquire()

            assert.has_error(function()
                pool:acquire()
            end)
        end)

        it("does not close legitimate long-running connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 10 })

            local conn = pool:acquire()
            pool.connections[1].last_used = os.time() - 20

            -- Alive abandoned connection is reclaimed, not discarded
            local new_conn = pool:acquire()
            assert.is_truthy(new_conn)
            assert.are.equal(1, #pool.connections)
            assert.are.equal(0, #driver.connections_closed)
        end)

        it("logs warning when reclaiming abandoned connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 10 })

            pool:acquire()
            pool.connections[1].last_used = os.time() - 20
            driver:mark_dead(pool.connections[1].connection)

            local captured = {}
            local original_write = io.write
            io.write = function(msg)
                table.insert(captured, msg)
            end

            pool:acquire()

            io.write = original_write

            assert.is_truthy(#captured >= 1)
            local found = false
            for _, msg in ipairs(captured) do
                if string.find(msg, "%[WARN%]") and string.find(msg, "recycled abandoned connection") then
                    found = true
                end
            end
            assert.is_true(found)
        end)

        it("respects custom abandoned_timeout value", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 30 })

            local conn = pool:acquire()
            pool.connections[1].last_used = os.time() - 25

            assert.has_error(function()
                pool:acquire()
            end)

            pool.connections[1].last_used = os.time() - 35
            driver:mark_dead(pool.connections[1].connection)

            local new_conn = pool:acquire()
            assert.is_truthy(new_conn)
        end)

        it("reclaims alive abandoned connection instead of discarding it", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 10 })

            local conn = pool:acquire()
            pool.connections[1].last_used = os.time() - 20
            -- Connection is alive (NOT marked dead)

            local new_conn = pool:acquire()
            assert.is_truthy(new_conn)
            -- Should reuse the same connection, not create a new one
            assert.are.equal(1, pool.created)
            assert.are.equal(1, #pool.connections)
        end)

        it("closes dead abandoned connection and creates new one", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1, abandoned_timeout = 10 })

            local conn = pool:acquire()
            local old_conn = pool.connections[1].connection
            pool.connections[1].last_used = os.time() - 20
            driver:mark_dead(pool.connections[1].connection)

            local new_conn = pool:acquire()
            assert.is_truthy(new_conn)
            assert.is_true(new_conn ~= old_conn)
            assert.are.equal(1, #driver.connections_closed)
        end)
    end)

    describe("execute", function()
        it("acquires, executes, and releases", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local result = pool:execute("SELECT 1")

            assert.is_truthy(result)
            assert.are.equal(0, pool.checked_out)
            assert.are.equal(2, #driver.execute_calls)
            assert.are.equal("SELECT 1", driver.execute_calls[2].sql)
        end)

        it("releases connection even when execute throws", function()
            local driver = mock_driver()
            driver.executeWithConnection = function(self, conn, sql, bindings)
                error("SQL error")
            end

            local pool = Pool.new(driver, { min_size = 1 })

            assert.has_error(function()
                pool:execute("BAD SQL")
            end)

            assert.are.equal(0, pool.checked_out)
        end)
    end)

    describe("close", function()
        it("closes all connections", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 3 })

            pool:close()

            assert.are.equal(0, pool.created)
            assert.are.equal(0, pool.checked_out)
            assert.are.equal(0, #pool.connections)
            assert.are.equal(3, #driver.connections_closed)
        end)
    end)
end)
