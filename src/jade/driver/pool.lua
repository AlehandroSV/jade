local Pool = {}
Pool.__index = Pool

function Pool.new(driver, options)
    options = options or {}
    local pool = setmetatable({
        driver = driver,
        connections = {},
        max_size = options.max_size or 10,
        min_size = options.min_size or 2,
        idle_timeout = options.idle_timeout or 300,
        created = 0,
        checked_out = 0,
    }, Pool)

    -- Pre-create min_size connections
    for i = 1, pool.min_size do
        local ok, conn = pcall(function() return driver:getConnection() end)
        if ok and conn then
            pool.created = pool.created + 1
            pool.connections[#pool.connections + 1] = {
                connection = conn,
                in_use = false,
                created_at = os.time(),
                last_used = os.time(),
            }
        end
    end

    return pool
end

function Pool:_isConnectionAlive(conn)
    -- Try a simple ping to check if connection is alive
    local ok, result = pcall(function()
        return self.driver:executeWithConnection(conn, "SELECT 1")
    end)
    return ok and result ~= nil
end

function Pool:_cleanIdleConnections()
    local now = os.time()
    local i = 1
    while i <= #self.connections do
        local entry = self.connections[i]
        if not entry.in_use and (now - entry.last_used) > self.idle_timeout then
            -- Connection is idle too long, close it
            pcall(function()
                if self.driver.closeConnection then
                    self.driver:closeConnection(entry.connection)
                else
                    self.driver:disconnect(entry.connection)
                end
            end)
            table.remove(self.connections, i)
            self.created = self.created - 1
        else
            i = i + 1
        end
    end
end

function Pool:acquire()
    -- Clean idle connections first
    self:_cleanIdleConnections()

    -- Try to get an idle connection with health check
    for i, conn in ipairs(self.connections) do
        if not conn.in_use then
            -- Check if connection is still alive
            if self:_isConnectionAlive(conn.connection) then
                conn.in_use = true
                conn.last_used = os.time()
                self.checked_out = self.checked_out + 1
                return conn.connection
            else
                -- Connection is dead, remove it
                pcall(function()
                    if self.driver.closeConnection then
                        self.driver:closeConnection(conn.connection)
                    else
                        self.driver:disconnect(conn.connection)
                    end
                end)
                table.remove(self.connections, i)
                self.created = self.created - 1
            end
        end
    end

    -- Create new connection if under max
    if self.created < self.max_size then
        local ok, conn = pcall(function() return self.driver:getConnection() end)
        if ok and conn then
            self.created = self.created + 1
            self.checked_out = self.checked_out + 1
            self.connections[#self.connections + 1] = {
                connection = conn,
                in_use = true,
                created_at = os.time(),
                last_used = os.time(),
            }
            return conn
        end
    end

    error("Connection pool exhausted (max: " .. self.max_size .. ")")
end

function Pool:release(conn)
    for _, entry in ipairs(self.connections) do
        if entry.connection == conn then
            entry.in_use = false
            entry.last_used = os.time()
            self.checked_out = self.checked_out - 1
            return
        end
    end
end

function Pool:close()
    for _, entry in ipairs(self.connections) do
        if entry.connection then
            pcall(function()
                if self.driver.closeConnection then
                    self.driver:closeConnection(entry.connection)
                else
                    self.driver:disconnect(entry.connection)
                end
            end)
        end
    end
    self.connections = {}
    self.created = 0
    self.checked_out = 0
end

function Pool:execute(sql, bindings)
    local conn = self:acquire()
    local ok, result = pcall(self.driver.executeWithConnection, self.driver, conn, sql, bindings)
    self:release(conn)
    if not ok then
        error(result)
    end
    return result
end

return Pool