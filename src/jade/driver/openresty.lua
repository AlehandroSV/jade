-- OpenResty driver using ngx.socket.tcp for non-blocking PostgreSQL queries
-- Requires OpenResty runtime

local ok_pg, PostgreSQL = pcall(require, "jade.driver.postgresql")
if not ok_pg then
    PostgreSQL = {}
end

local OpenResty = setmetatable({}, { __index = PostgreSQL })
OpenResty.__index = OpenResty

OpenResty._driver_type = "openresty"

-- Check if ngx is available
local ok_ngx, ngx = pcall(require, "ngx")
if not ok_ngx then
    ngx = nil
end

function OpenResty.new()
    local self = setmetatable(PostgreSQL.new and PostgreSQL.new() or {}, OpenResty)
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
    if not ngx then
        error("OpenResty driver requires ngx runtime")
    end

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
    local results = {}
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

        -- Parse PostgreSQL wire protocol response
        -- Response format: 1 byte type + 4 bytes length + data
        while true do
            local header, header_err = sock:receive(5)
            if not header then
                break
            end

            local msg_type = header:sub(1, 1)
            local msg_len = header:byte(2) * 256 * 256 * 256 +
                           header:byte(3) * 256 * 256 +
                           header:byte(4) * 256 +
                           header:byte(5) - 4

            if msg_type == "T" then
                -- Row Description: parse column info
                -- Skip for now, we'll use simple parsing
                sock:receive(msg_len)
            elseif msg_type == "D" then
                -- Data Row: parse row data
                local row_data = sock:receive(msg_len)
                if row_data then
                    local num_fields = row_data:byte(1) * 256 + row_data:byte(2)
                    local row = {}
                    local pos = 3
                    for i = 1, num_fields do
                        local field_len = row_data:byte(pos) * 256 * 256 * 256 +
                                         row_data:byte(pos + 1) * 256 * 256 +
                                         row_data:byte(pos + 2) * 256 +
                                         row_data:byte(pos + 3)
                        pos = pos + 4
                        if field_len == -1 or field_len == 4294967295 then
                            -- NULL value
                            row[i] = nil
                        else
                            row[i] = row_data:sub(pos, pos + field_len - 1)
                            pos = pos + field_len
                        end
                    end
                    results[#results + 1] = row
                end
            elseif msg_type == "C" then
                -- Command Complete
                sock:receive(msg_len)
                break
            elseif msg_type == "E" then
                -- Error
                local error_data = sock:receive(msg_len)
                if error_data then
                    error("PostgreSQL error: " .. error_data)
                end
                break
            elseif msg_type == "Z" then
                -- Ready for Query
                sock:receive(msg_len)
                break
            else
                -- Unknown message type, skip
                sock:receive(msg_len)
            end
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

    return results
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
