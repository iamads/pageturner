-- Nonblocking LuaSocket transport polled by KOReader's existing UIManager ZMQ hook.
-- Bounded work, no threads, raw-header logs, InputEvents, or global timing changes.
local socket = require("socket")
local HTTP = require("pageturner_http")
local Server = {}
Server.__index = Server

function Server:new(options)
    return setmetatable({
        port = options.port,
        on_request = options.on_request,
        now = options.now or socket.gettime,
        clients = {},
        max_clients = 4,
        max_header = 4096,
        client_timeout = 2,
    }, self)
end

function Server:start()
    local listener, err = socket.bind("0.0.0.0", self.port, self.max_clients)
    if not listener then return nil, err end
    listener:settimeout(0)
    self.listener = listener
    return true
end

function Server:stop()
    if self.listener then self.listener:close(); self.listener = nil end
    for _, client in ipairs(self.clients) do client.socket:close() end
    self.clients = {}
end

function Server:readRequest(client)
    -- Numeric receive consumes at most the remaining header budget, even if a
    -- malicious peer never sends a newline. Partial reads persist across ticks.
    local data, err, partial = client.socket:receive(self.max_header - #client.input)
    client.input = client.input .. (data or partial or "")
    if client.input:find("\r\n\r\n", 1, true) then
        local ok, response = pcall(self.on_request, client.input)
        client.output = ok and response or HTTP.response(500, "Request handler failed")
        client.input = nil
        client.sent = 0
    elseif #client.input >= self.max_header then
        client.output = HTTP.response(431, "Headers exceed 4096 bytes")
        client.input = nil
        client.sent = 0
    elseif err and err ~= "timeout" then
        return false
    end
    return true
end

function Server:waitEvent()
    if not self.listener then return end
    -- Accept at most one connection and service at most four clients per tick.
    -- Returning nil deliberately avoids UIManager emitting an InputEvent, which
    -- would otherwise reset KOReader's existing inactivity timers.
    if #self.clients < self.max_clients then
        local peer = self.listener:accept()
        if peer then
            peer:settimeout(0)
            self.clients[#self.clients + 1] = {
                socket = peer, input = "", expires = self.now() + self.client_timeout,
            }
        end
    end
    for i = #self.clients, 1, -1 do
        local client = self.clients[i]
        local keep = self.now() < client.expires
        if keep and not client.output then keep = self:readRequest(client) end
        if keep and client.output then
            local sent, err, partial = client.socket:send(client.output, client.sent + 1)
            -- LuaSocket returns the last byte index, not the number written.
            client.sent = sent or partial or client.sent
            keep = client.sent < #client.output and (not err or err == "timeout")
        end
        if not keep then
            client.socket:close()
            table.remove(self.clients, i)
        end
    end
end

return Server
