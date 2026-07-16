local Pool = {}
Pool.__index = Pool

function Pool.new(driver, options)
    options = options or {}
    return setmetatable({
        driver = driver,
        connections = {},
        max_size = options.max_size or 10,
        min_size = options.min_size or 2,
        idle_timeout = options.idle_timeout or 300,
        created = 0,
        checked_out = 0,
    }, Pool)
end

function Pool:acquire()
    -- Try to get an idle connection
    for i, conn in ipairs(self.connections) do
        if not conn.in_use then
            conn.in_use = true
            conn.last_used = os.time()
            self.checked_out = self.checked_out + 1
            return conn.connection
        end
    end

    -- Create new connection if under max
    if self.created < self.max_size then
        local conn = self.driver:getConnection()
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
                self.driver:disconnect(entry.connection)
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