describe("Connection Pool", function()
    local Pool = require("jade.driver.pool")

    local function mock_driver()
        local conn_counter = 0
        local driver = {
            connections_created = {},
            connections_closed = {},
            execute_calls = {},
            dead_connections = {},
            tx_log = {},
            auto_commit_statements = {},
            tx_statements = {},
            _in_tx = false,
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
            if driver._in_tx then
                table.insert(driver.tx_statements, { conn = conn, sql = sql })
            elseif sql ~= "SELECT 1" then
                table.insert(driver.auto_commit_statements, { conn = conn, sql = sql })
            end
            return { rows = {}, affected = 1 }
        end

        function driver:beginTransaction(conn)
            table.insert(driver.tx_log, { op = "BEGIN", conn = conn })
            driver._in_tx = true
            driver.tx_statements = {}
        end

        function driver:commitTransaction(conn)
            table.insert(driver.tx_log, { op = "COMMIT", conn = conn })
            for _, stmt in ipairs(driver.tx_statements) do
                table.insert(driver.auto_commit_statements, stmt)
            end
            driver.tx_statements = {}
            driver._in_tx = false
        end

        function driver:rollbackTransaction(conn)
            table.insert(driver.tx_log, { op = "ROLLBACK", conn = conn })
            driver.tx_statements = {}
            driver._in_tx = false
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

    describe("transaction", function()
        it("binds entire fn to one leased connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2 })

            pool:transaction(function()
                pool:execute("INSERT INTO t1 VALUES (1)")
                pool:execute("INSERT INTO t1 VALUES (2)")
            end)

            assert.are.equal(2, #driver.tx_log)
            assert.are.equal("BEGIN", driver.tx_log[1].op)
            assert.are.equal("COMMIT", driver.tx_log[2].op)

            local tx_conn = driver.tx_log[1].conn
            assert.are.equal(tx_conn, driver.tx_log[2].conn)
            for _, stmt in ipairs(driver.tx_statements) do
                assert.are.equal(tx_conn, stmt.conn)
            end
            -- statements were flushed to auto_commit on COMMIT
            assert.are.equal(2, #driver.auto_commit_statements)
            assert.are.equal(tx_conn, driver.auto_commit_statements[1].conn)
            assert.are.equal(tx_conn, driver.auto_commit_statements[2].conn)
        end)

        it("routes execute during transaction to the same connection (issue #175)", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2 })

            local conns_seen = {}
            pool:transaction(function()
                pool:execute("CREATE TABLE t1 (id INTEGER)")
                table.insert(conns_seen, pool._tx_conn)
                pool:execute("INSERT INTO t1 VALUES (1)")
                table.insert(conns_seen, pool._tx_conn)
            end)

            assert.is_truthy(conns_seen[1])
            assert.are.equal(conns_seen[1], conns_seen[2])
            assert.are.equal(driver.tx_log[1].conn, conns_seen[1])
        end)

        it("commits on success and releases the connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local result = pool:transaction(function()
                pool:execute("INSERT INTO t1 VALUES (1)")
                return "payload"
            end)

            assert.are.equal("payload", result)
            assert.are.equal(0, pool.checked_out)
            assert.is_nil(pool._tx_conn)
            assert.are.equal("COMMIT", driver.tx_log[2].op)
        end)

        it("rolls back on error and does not leave partial writes", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            assert.has_error(function()
                pool:transaction(function()
                    pool:execute("CREATE TABLE t1 (id INTEGER)")
                    pool:execute("INSERT INTO t1 VALUES (1)")
                    error("mid-tx failure")
                end)
            end)

            assert.are.equal(2, #driver.tx_log)
            assert.are.equal("BEGIN", driver.tx_log[1].op)
            assert.are.equal("ROLLBACK", driver.tx_log[2].op)

            -- nothing from the failed tx became durable
            assert.are.equal(0, #driver.auto_commit_statements)
            assert.are.equal(0, pool.checked_out)
            assert.is_nil(pool._tx_conn)
        end)

        it("releases the leased connection after mid-tx failure", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1, max_size = 1 })

            assert.has_error(function()
                pool:transaction(function()
                    error("boom")
                end)
            end)

            assert.are.equal(0, pool.checked_out)

            local conn = pool:acquire()
            assert.is_truthy(conn)
            pool:release(conn)
        end)

        it("does not commit when a statement inside fn fails", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            local original = driver.executeWithConnection
            function driver:executeWithConnection(conn, sql, bindings)
                if sql == "INSERT INTO t1 VALUES (2)" then
                    table.insert(self.execute_calls, { conn = conn, sql = sql, bindings = bindings })
                    error("constraint violation")
                end
                return original(self, conn, sql, bindings)
            end

            assert.has_error(function()
                pool:transaction(function()
                    pool:execute("INSERT INTO t1 VALUES (1)")
                    pool:execute("INSERT INTO t1 VALUES (2)")
                end)
            end)

            assert.are.equal("ROLLBACK", driver.tx_log[2].op)
            assert.are.equal(0, #driver.auto_commit_statements)
            assert.are.equal(0, pool.checked_out)
        end)

        it("nested transaction joins the outer sticky connection", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2 })

            local outer_conn, inner_conn
            pool:transaction(function()
                outer_conn = pool._tx_conn
                pool:transaction(function()
                    inner_conn = pool._tx_conn
                    pool:execute("INSERT INTO t1 VALUES (1)")
                end)
                pool:execute("INSERT INTO t1 VALUES (2)")
            end)

            assert.are.equal(outer_conn, inner_conn)
            -- only one BEGIN/COMMIT pair
            assert.are.equal(2, #driver.tx_log)
            assert.are.equal(0, pool.checked_out)
            assert.are.equal(2, #driver.auto_commit_statements)
        end)

        it("uses pool execute path after transaction ends", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 2 })

            pool:transaction(function()
                pool:execute("INSERT INTO t1 VALUES (1)")
            end)

            pool:execute("INSERT INTO t1 VALUES (3)")

            assert.is_nil(pool._tx_conn)
            assert.are.equal(2, #driver.auto_commit_statements)
            assert.are.equal(0, pool.checked_out)
        end)

        it("does not mark tx statements as auto-commit before commit", function()
            local driver = mock_driver()
            local pool = Pool.new(driver, { min_size = 1 })

            pool:transaction(function()
                pool:execute("INSERT INTO t1 VALUES (1)")
                assert.are.equal(0, #driver.auto_commit_statements)
                assert.are.equal(1, #driver.tx_statements)
            end)

            assert.are.equal(1, #driver.auto_commit_statements)
        end)
    end)

    describe("driver:transaction pool delegation (issue #175)", function()
        local function stub_pool_tx()
            local calls = {}
            local pool = {
                transaction = function(self, fn)
                    calls[#calls + 1] = true
                    return fn()
                end,
            }
            return pool, calls
        end

        it("SQLite:transaction uses pool when configured", function()
            local SQLite = require("jade.driver.sqlite")
            local driver = SQLite.new()
            local pool, calls = stub_pool_tx()
            driver._pool = pool

            local ran = false
            driver:transaction(function()
                ran = true
            end)

            assert.is_true(ran)
            assert.are.equal(1, #calls)
        end)

        it("MySQL:transaction uses pool when configured", function()
            local MySQL = require("jade.driver.mysql")
            local driver = MySQL.new()
            local pool, calls = stub_pool_tx()
            driver._pool = pool

            local ran = false
            driver:transaction(function()
                ran = true
            end)

            assert.is_true(ran)
            assert.are.equal(1, #calls)
        end)

        it("PostgreSQL:transaction uses pool when configured", function()
            local PostgreSQL = require("jade.driver.postgresql")
            local driver = PostgreSQL.new()
            local pool, calls = stub_pool_tx()
            driver._pool = pool

            local ran = false
            driver:transaction(function()
                ran = true
            end)

            assert.is_true(ran)
            assert.are.equal(1, #calls)
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
