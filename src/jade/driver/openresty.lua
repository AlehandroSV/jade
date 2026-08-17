-- OpenResty driver using ngx.socket.tcp for non-blocking PostgreSQL queries
-- Requires OpenResty runtime

local PostgreSQL = require("jade.driver.postgresql")

local OpenResty = setmetatable({}, { __index = PostgreSQL })
OpenResty.__index = OpenResty

OpenResty._driver_type = "openresty"

function OpenResty.new()
    local self = setmetatable(PostgreSQL.new(), OpenResty)
    self._pool_size = 10
    self._pool_timeout = 10000  -- ms
    self._sock = nil
    return self
end

function OpenResty:connect(opts)
    if not ngx then
        error("OpenResty driver requires ngx runtime")
    end

    self._host = opts.host or "127.0.0.1"
    self._port = opts.port or 5432
    self._database = opts.database
    self._user = opts.user
    self._password = opts.password
    self._ssl = opts.ssl or false
    self._ssl_verify = opts.ssl_verify or false
    self._pool_size = opts.pool_size or self._pool_size
    self._pool_timeout = opts.pool_timeout or self._pool_timeout

    self._connected = true
end

function OpenResty:_get_socket()
    local sock = ngx.socket.tcp()
    sock:settimeout(self._pool_timeout)

    local ok, err = sock:connect(self._host, self._port)
    if not ok then
        error("Failed to connect to " .. self._host .. ":" .. self._port .. ": " .. tostring(err))
    end

    if self._ssl then
        local session, ssl_err = sock:sslhandshake(nil, self._host, self._ssl_verify)
        if not session then
            error("SSL handshake failed: " .. tostring(ssl_err))
        end
    end

    return sock
end

function OpenResty:execute(sql, bindings)
    local sock = self:_get_socket()
    local ok, err = pcall(function()
        -- Use PostgreSQL simple query protocol
        local query = sql
        if bindings and #bindings > 0 then
            -- Replace ? placeholders with $1, $2, etc.
            local i = 0
            query = query:gsub("%?", function()
                i = i + 1
                return "$" .. i
            end)
        end

        -- Send query
        local len = #query + 4 + 1  -- 4 bytes length + 1 byte null terminator
        local packet = string.char(
            math.floor(len / 256 / 256 / 256) % 256,
            math.floor(len / 256 / 256) % 256,
            math.floor(len / 256) % 256,
            len % 256
        ) .. "Q" .. query .. "\0"

        sock:send(packet)

        -- Read response (simplified — real implementation would parse PostgreSQL wire protocol)
        local data, err = sock:receive("*l")
        if not data then
            error("Query failed: " .. tostring(err))
        end
    end)

    -- Return to pool
    if self._pool_size > 0 then
        local ok_pool, err_pool = sock:setkeepalive(self._pool_timeout, self._pool_size)
        if not ok_pool then
            sock:close()
        end
    else
        sock:close()
    end

    if not ok then
        error(err)
    end

    return {}
end

function OpenResty:getConnection()
    return self:_get_socket()
end

function OpenResty:closeConnection(sock)
    if sock then
        sock:close()
    end
end

function OpenResty:disconnect()
    self._connected = false
end

return OpenResty
