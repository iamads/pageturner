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
        on_diagnostic = options.on_diagnostic,
        now = options.now or socket.gettime,
        clients = {},
        connection_sequence = 0,
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

-- One diagnostic per state transition, never per polling tick. Logging failures
-- must not interrupt reading; callers receive only fixed labels and numbers.
function Server:diagnostic(client, event, detail)
    if self.on_diagnostic then
        pcall(self.on_diagnostic, client.id, event, detail or "")
    end
end

function Server:stop()
    if self.listener then self.listener:close(); self.listener = nil end
    for _, client in ipairs(self.clients) do
        self:diagnostic(client, "closed", "listener_stopped")
        client.socket:close()
    end
    self.clients = {}
end

function Server:readRequest(client)
    -- Numeric receive consumes at most the remaining header budget, even if a
    -- malicious peer never sends a newline. Partial reads persist across ticks.
    local data, err, partial = client.socket:receive(self.max_header - #client.input)
    client.input = client.input .. (data or partial or "")
    if client.input:find("\r\n\r\n", 1, true) then
        self:diagnostic(client, "request", HTTP.requestSummary(client.input))
        local ok, response = pcall(self.on_request, client.input)
        client.output = ok and response or HTTP.response(500, "Request handler failed")
        self:diagnostic(client, "response_status", tonumber(client.output:match("^HTTP/1%.1 (%d%d%d) ")) or 0)
        client.input = nil
        client.sent = 0
    elseif #client.input >= self.max_header then
        client.output = HTTP.response(431, "Headers exceed 4096 bytes")
        self:diagnostic(client, "response_status", 431)
        client.input = nil
        client.sent = 0
    elseif err and err ~= "timeout" then
        client.close_reason = "read_closed_or_error"
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
            self.connection_sequence = self.connection_sequence + 1
            local client = {
                id = self.connection_sequence,
                socket = peer, input = "", expires = self.now() + self.client_timeout,
            }
            self.clients[#self.clients + 1] = client
            self:diagnostic(client, "connected")
        end
    end
    for i = #self.clients, 1, -1 do
        local client = self.clients[i]
        local keep = self.now() < client.expires
        if not keep then client.close_reason = "timeout" end
        if keep and not client.output then keep = self:readRequest(client) end
        if keep and client.output then
            local sent, err, partial = client.socket:send(client.output, client.sent + 1)
            -- LuaSocket returns the last byte index, not the number written.
            client.sent = sent or partial or client.sent
            keep = client.sent < #client.output and (not err or err == "timeout")
            if not keep then
                client.close_reason = client.sent >= #client.output and "response_sent" or "write_error"
            end
        end
        if not keep then
            self:diagnostic(client, "closed", client.close_reason)
            client.socket:close()
            table.remove(self.clients, i)
        end
    end
end

return Server
