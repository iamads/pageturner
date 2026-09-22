-- Run from the project root: luajit tests/test_plugin.lua
-- KOReader/LuaSocket doubles exercise logic without pretending to be device tests.
package.path = "pageturner.koplugin/?.lua;" .. package.path
local count = 0
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, fn)
    fn()
    count = count + 1
    print("ok " .. count .. " - " .. name)
end
local token = string.rep("a", 48)
local function request(path, auth, method, headers)
    return (method or "POST") .. " " .. (path or "/next") .. " HTTP/1.1\r\n"
        .. "Authorization: Bearer " .. (auth or token) .. "\r\n"
        .. (headers or "Content-Length: 0\r\n") .. "\r\n"
end
local function browserRequest(path, auth, origin, headers)
    return "POST " .. (path or "/next") .. " HTTP/1.1\r\n"
        .. "Origin: " .. (origin or "https://iamads.github.io") .. "\r\n"
        .. "Authorization: Bearer " .. (auth or token) .. "\r\n"
        .. (headers or "Content-Length: 0\r\n") .. "\r\n"
end
local function preflight(path, origin, method, headers, private_network)
    return "OPTIONS " .. (path or "/next") .. " HTTP/1.1\r\n"
        .. "Origin: " .. (origin or "https://iamads.github.io") .. "\r\n"
        .. "Access-Control-Request-Method: " .. (method or "POST") .. "\r\n"
        .. "Access-Control-Request-Headers: " .. (headers or "authorization") .. "\r\n"
        .. (private_network and "Access-Control-Request-Private-Network: " .. private_network .. "\r\n" or "")
        .. "\r\n"
end
local Pairing = require("pageturner_pairing")
local Endpoint = require("pageturner_endpoint")
test("pairing token uses 32 secure random bytes and produces JSON-safe hex", function()
    local bytes = string.char(0, 1, 15, 16, 254, 255) .. string.rep("z", 26)
    local generated = assert(Pairing.generateToken(function(count) eq(count, 32); return bytes end))
    eq(#generated, 64)
    eq(generated:sub(1, 12), "00010f10feff")
    assert(generated:match("^[a-f0-9]+$"))
    eq(Pairing.generateToken(function() return "short" end), nil)
end)
test("pairing payload is a camera-readable HTTPS link with fragment-only credentials", function()
    local prefix = "https://iamads.github.io/pageturner/#version=1&endpoint="
    local payload = assert(Pairing.payload("https://kindle.example.ts.net", token))
    eq(payload, prefix .. 'https%3A%2F%2Fkindle.example.ts.net&token=' .. token)
    eq(Pairing.payload("http://192.168.1.42:8088", token),
        prefix .. 'http%3A%2F%2F192.168.1.42%3A8088&token=' .. token)
    eq(payload:match("^(.-)#"), "https://iamads.github.io/pageturner/")
    eq(Pairing.payload("https://kindle.example.ts.net/next", token), nil)
    eq(Pairing.payload("https://kindle.example.ts.net", "short"), nil)
    eq(Pairing.payload("https://kindle.example.ts.net#bad", token), nil)
    eq(Pairing.payload("https://kindle.example.ts.net?bad", token), nil)
end)
test("endpoint resolver selects only Serve mapped to the current backend", function()
    local status = "https://kindle.example.ts.net (tailnet only)\n"
        .. "|-- / proxy http://127.0.0.1:8088\n"
    eq(Endpoint.parseServeStatus(status, 8088), "https://kindle.example.ts.net")
    eq(Endpoint.parseServeStatus(status, 8089), nil)
    eq(Endpoint.parseServeStatus("https://evil.example\n|-- / proxy http://127.0.0.1:8088", 8088), nil)
    eq(Endpoint.localUrl({address = "192.168.1.42"}, 8088), "http://192.168.1.42:8088")
    eq(Endpoint.localUrl({}, 8088), nil)
end)
test("Serve probe command is fixed, bounded and contains no pairing secret", function()
    local command
    local path = Endpoint.startServeProbe(7, function(value) command = value; return 0 end)
    eq(path, "/tmp/pageturner-serve-status-7.log")
    assert(command:find("timeout -t 3", 1, true))
    assert(command:find("serve status", 1, true))
    assert(not command:find(token, 1, true))
    Endpoint.cancelServeProbe(path)
end)

local HTTP = require("pageturner_http")
test("only next/back map to signed reader navigation", function()
    eq(HTTP.command(request(), token), 1)
    eq(HTTP.command(request("/back"), token), -1)
    local direction, status = HTTP.command(request("/event/GotoViewRel/1"), token)
    eq(direction, nil); eq(status, 404)
end)
test("authentication fails closed", function()
    for _, data in ipairs({request(nil, "wrong"), "POST /next HTTP/1.1\r\n\r\n"}) do
        local direction, status = HTTP.command(data, token)
        eq(direction, nil); eq(status, 401)
    end
    eq(select(2, HTTP.command(request(), nil)), 401)
end)
test("reject methods, bodies, duplicates, pipelining and malformed headers", function()
    eq(select(2, HTTP.command(request(nil, nil, "GET"), token)), 405)
    eq(select(2, HTTP.command(request(nil, nil, nil, "Content-Length: 1\r\n"), token)), 400)
    eq(select(2, HTTP.command(request(nil, nil, nil, "Transfer-Encoding: chunked\r\n"), token)), 400)
    eq(select(2, HTTP.command(request(nil, nil, nil, "Expect: 100-continue\r\n"), token)), 400)
    eq(select(2, HTTP.command(request(nil, nil, nil, "authorization: Bearer " .. token .. "\r\n"), token)), 400)
    eq(select(2, HTTP.command(request() .. request(), token)), 400)
    eq(select(2, HTTP.command(request(nil, nil, nil, "bad header\r\n"), token)), 400)
    eq(select(2, HTTP.command("nonsense", token)), 400)
end)
test("response framing has exact body length and connection close", function()
    local response = HTTP.response(202, "accepted")
    assert(response:find("Content-Length: 9\r\n", 1, true))
    assert(response:find("Connection: close\r\n", 1, true))
    eq(response:match("\r\n\r\n(.*)$"), "accepted\n")
end)
test("approved preflight grants only fixed command and connection CORS permissions", function()
    for _, path in ipairs({"/next", "/back", "/connect"}) do
        local response = HTTP.preflight(preflight(path))
        assert(response:find("HTTP/1.1 204 No Content", 1, true))
        assert(response:find("Access-Control-Allow-Origin: https://iamads.github.io\r\n", 1, true))
        assert(response:find("Access-Control-Allow-Methods: POST\r\n", 1, true))
        assert(response:find("Access-Control-Allow-Headers: Authorization\r\n", 1, true))
        assert(response:find("Vary: Origin\r\n", 1, true))
        assert(not response:find("Access-Control-Allow-Private-Network", 1, true))
        eq(response:match("Content%-Length: (%d+)"), "0")
        eq(response:match("\r\n\r\n(.*)$"), "")
    end
    local private = HTTP.preflight(preflight("/next", nil, nil, nil, "true"))
    assert(private:find("Access-Control-Allow-Private-Network: true\r\n", 1, true))
end)
test("preflight rejects every broader origin, route, method, header and body", function()
    local rejected = {
        preflight("/next", "https://evil.example"),
        preflight("/other"),
        preflight("/next", nil, "GET"),
        preflight("/next", nil, nil, "content-type"),
        preflight("/next", nil, nil, "authorization, content-type"),
        preflight("/next", nil, nil, "authorization, authorization"),
        preflight("/next", nil, nil, nil, "false"),
        (preflight("/next"):gsub("\r\n\r\n$", "\r\nContent-Length: 1\r\n\r\nx")),
    }
    for _, data in ipairs(rejected) do
        local response = HTTP.preflight(data)
        assert(response and not response:find("204 No Content", 1, true))
        assert(not response:find("Access-Control-Allow-Methods", 1, true))
    end
end)
test("actual browser commands retain auth and expose only approved-origin responses", function()
    local direction, status, message, cors = HTTP.command(browserRequest(), token)
    eq(direction, 1); eq(status, nil); eq(message, nil); eq(cors, true)
    direction, status, message, cors = HTTP.command(browserRequest("/back", "wrong"), token)
    eq(direction, nil); eq(status, 401); eq(cors, true)
    direction, status, message, cors = HTTP.command(browserRequest("/next", token, "https://evil.example"), token)
    eq(direction, nil); eq(status, 403); eq(cors, false)
    local allowed = HTTP.response(401, "no", {cors = true})
    assert(allowed:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    assert(not allowed:find("Access-Control-Allow-Methods", 1, true))
    assert(not HTTP.response(401, "no"):find("Access-Control-Allow-Origin", 1, true))
end)

test("diagnostics classify browser preflight without raw request values", function()
    local data = "OPTIONS /next HTTP/1.1\r\nOrigin: https://iamads.github.io\r\n"
        .. "Access-Control-Request-Method: POST\r\n"
        .. "Access-Control-Request-Headers: Authorization\r\n"
        .. "Access-Control-Request-Private-Network: true\r\n\r\n"
    eq(HTTP.requestSummary(data), "method=OPTIONS route=/next origin=pages auth=absent"
        .. " requested_method=POST requested_headers=authorization private_network=true")
    -- The command parser still requires auth; PageTurner handles valid OPTIONS
    -- through HTTP.preflight before command parsing.
    eq(select(2, HTTP.command(data, token)), 401)
end)
test("diagnostics never echo tokens in URLs, headers, methods or malformed input", function()
    for _, data in ipairs({
        request("/next?token=" .. token),
        request("/" .. token, token, "POST", "Origin: " .. token .. "\r\n"
            .. "Access-Control-Request-Method: " .. token .. "\r\n"
            .. "Access-Control-Request-Headers: " .. token .. "\r\n"
            .. "Access-Control-Request-Private-Network: " .. token .. "\r\n"),
        token .. " /next HTTP/1.1\r\n\r\n",
        "garbage " .. token .. "\r\n\r\n",
        request() .. token,
    }) do
        local summary = HTTP.requestSummary(data)
        assert(not summary:find(token, 1, true))
        assert(not summary:find("[\r\n]"))
        assert(#summary < 220)
    end
    local duplicate = request(nil, nil, nil,
        "Origin: https://iamads.github.io\r\norigin: " .. token .. "\r\n")
    assert(HTTP.requestSummary(duplicate):find("origin=other", 1, true))
end)

local clock = 0
local incoming = {}
local bind_error
local last_listener
local function peer(chunks, send_limit)
    return {
        chunks = chunks or {}, output = "", closed = false,
        settimeout = function(_, value) eq(value, 0) end,
        receive = function(self, n)
            local chunk = table.remove(self.chunks, 1)
            if not chunk then return nil, "timeout", "" end
            if #chunk > n then table.insert(self.chunks, 1, chunk:sub(n + 1)); chunk = chunk:sub(1, n) end
            return nil, "timeout", chunk
        end,
        send = function(self, data, start)
            local last = math.min(#data, start + (send_limit or #data) - 1)
            self.output = self.output .. data:sub(start, last)
            if last == #data then return last end
            return nil, "timeout", last
        end,
        close = function(self) self.closed = true end,
    }
end
package.loaded.socket = {
    gettime = function() return clock end,
    bind = function(host, port)
        eq(host, "0.0.0.0")
        if bind_error then return nil, bind_error end
        last_listener = {
            settimeout = function(_, value) eq(value, 0) end,
            accept = function() return table.remove(incoming, 1) end,
            close = function(self) self.closed = true end,
        }
        return last_listener
    end,
}
local Server = require("pageturner_server")
test("fragmented request, partial response, one dispatch, no InputEvent", function()
    local calls = 0
    local server = Server:new{port = 8088, on_request = function(data)
        calls = calls + 1
        eq(HTTP.command(data, token), 1)
        return HTTP.response(202, "accepted")
    end}
    assert(server:start())
    local data = request()
    local client = peer({data:sub(1, 17), data:sub(18)}, 7)
    incoming = {client}
    eq(server:waitEvent(), nil); eq(calls, 0)
    for _ = 1, 100 do eq(server:waitEvent(), nil) end
    eq(calls, 1); eq(client.closed, true)
    eq(client.output, HTTP.response(202, "accepted"))
    server:stop(); eq(last_listener.closed, true)
end)
test("slow clients expire and oversized headers never dispatch", function()
    local calls = 0
    local server = Server:new{port = 8088, on_request = function() calls = calls + 1 end}
    assert(server:start())
    local slow = peer({"POST"})
    incoming = {slow}; server:waitEvent()
    clock = clock + 3; server:waitEvent()
    eq(slow.closed, true)
    local large = peer({string.rep("x", 10000)})
    incoming = {large}; server:waitEvent()
    assert(large.output:find("431", 1, true)); eq(large.closed, true); eq(calls, 0)
    server:stop()
end)
test("client count and cleanup are bounded", function()
    local server = Server:new{port = 8088, on_request = function() error("unexpected") end}
    assert(server:start())
    incoming = {peer(), peer(), peer(), peer(), peer()}
    for _ = 1, 10 do server:waitEvent() end
    eq(#server.clients, 4); eq(#incoming, 1)
    local clients = server.clients
    server:stop()
    for _, client in ipairs(clients) do eq(client.socket.closed, true) end
    incoming = {}
end)
test("handler failure becomes a safe response", function()
    local server = Server:new{port = 8088, on_request = function() error(token) end}
    assert(server:start())
    local client = peer({request()}); incoming = {client}; server:waitEvent()
    assert(client.output:find("500", 1, true)); assert(not client.output:find(token, 1, true))
    server:stop()
end)

local function diagnosticServer(handler)
    local entries = {}
    local server = Server:new{port = 8088, on_request = handler or function(data)
        local direction, status, message = HTTP.command(data, token)
        return HTTP.response(direction and 202 or status, direction and "accepted" or message)
    end, on_diagnostic = function(id, event, detail)
        entries[#entries + 1] = id .. " " .. event .. " " .. detail
    end}
    assert(server:start())
    return server, entries
end
test("transport logs each request and status once despite partial I/O", function()
    local server, entries = diagnosticServer()
    local data = request()
    local client = peer({data:sub(1, 20), data:sub(21)}, 7)
    incoming = {client}
    for _ = 1, 100 do eq(server:waitEvent(), nil) end
    eq(#entries, 4)
    eq(entries[1], "1 connected ")
    eq(entries[2], "1 request " .. HTTP.requestSummary(data))
    eq(entries[3], "1 response_status 202")
    eq(entries[4], "1 closed response_sent")
    assert(not table.concat(entries):find(token, 1, true))
    server:stop()
end)
test("transport distinguishes timeout, header limit, read error and stop", function()
    local server, entries = diagnosticServer()
    incoming = {peer({"partial"})}; server:waitEvent()
    clock = clock + 3; server:waitEvent()
    eq(entries[2], "1 closed timeout")
    incoming = {peer({string.rep("x", 5000)})}; server:waitEvent()
    eq(entries[4], "2 response_status 431")
    eq(entries[5], "2 closed response_sent")
    local disconnected = peer()
    disconnected.receive = function() return nil, "closed", "" end
    incoming = {disconnected}; server:waitEvent()
    eq(entries[7], "3 closed read_closed_or_error")
    incoming = {peer()}; server:waitEvent(); server:stop()
    eq(entries[9], "4 closed listener_stopped")
end)
test("transport handler and send failures log safe statuses, not errors", function()
    local server, entries = diagnosticServer(function() error(token) end)
    local client = peer({request()})
    client.send = function() return nil, token, 0 end
    incoming = {client}; server:waitEvent()
    eq(entries[3], "1 response_status 500")
    eq(entries[4], "1 closed write_error")
    assert(not table.concat(entries):find(token, 1, true))
    server:stop()
end)
test("broken diagnostic callback cannot break requests or cleanup", function()
    local server = diagnosticServer()
    server.on_diagnostic = function() error("logging unavailable") end
    local client = peer({request()})
    incoming = {client}; server:waitEvent()
    assert(client.output:find("202 Accepted", 1, true)); eq(client.closed, true)
    server:stop()
end)

local Firewall = require("pageturner_firewall")
test("firewall owns a chain, reverses its rules, and is idempotent", function()
    local commands = {}
    local firewall = Firewall:new(8088, function(command) commands[#commands + 1] = command; return 0 end)
    assert(firewall:open()); eq(#commands, 4)
    assert(firewall:close()); eq(#commands, 8)
    eq(commands[1], "iptables -N KR_PAGETURNER")
    eq(commands[5], "iptables -D OUTPUT -p tcp --sport 8088 -j KR_PAGETURNER")
    eq(commands[8], "iptables -X KR_PAGETURNER")
    assert(firewall:close()); eq(#commands, 8)
end)
test("firewall creation failure never removes someone else's chain", function()
    local calls = 0
    local firewall = Firewall:new(8088, function() calls = calls + 1; return 1 end)
    eq(firewall:open(), nil); eq(calls, 1)
    assert(firewall:close()); eq(calls, 1)
end)
test("firewall partial startup rolls back; cleanup failure can retry", function()
    local calls, fail = 0, true
    local firewall = Firewall:new(8088, function()
        calls = calls + 1
        if calls == 4 or (fail and calls > 4) then return 1 end
        return 0
    end)
    eq(firewall:open(), nil); eq(#firewall.undo, 3)
    fail = false
    assert(firewall:close()); eq(#firewall.undo, 0)
end)
test("firewall validates port before shell interpolation", function()
    eq(pcall(function() Firewall:new("8088; bad") end), false)
    eq(pcall(function() Firewall:new(8088.5) end), false)
end)

local Widget = {}
function Widget:extend(t) t = t or {}; t.__index = t; return setmetatable(t, {__index = self}) end
function Widget:new(t) t = setmetatable(t or {}, self); if t.init then t:init() end; return t end
local manager = {tasks = {}, queues = {}, shown = {}}
function manager:nextTick(fn) self.tasks[#self.tasks + 1] = fn end
function manager:scheduleIn(_, fn) self.tasks[#self.tasks + 1] = fn end
function manager:unschedule(fn)
    for i = #self.tasks, 1, -1 do if self.tasks[i] == fn then table.remove(self.tasks, i) end end
end
function manager:insertZMQ(server) self.queues[server] = true end
function manager:removeZMQ(server) self.queues[server] = nil end
function manager:getTopmostVisibleWidget() return self.top end
function manager:show(widget) self.shown[#self.shown + 1] = widget end
function manager:close(widget) widget.closed = true end
function manager:tick() local tasks = self.tasks; self.tasks = {}; for _, fn in ipairs(tasks) do fn() end end
package.loaded["ui/widget/container/widgetcontainer"] = Widget
package.loaded["ui/uimanager"] = manager
package.loaded["ui/event"] = {new = function(_, name, direction) return {name = name, direction = direction} end}
package.loaded["ui/time"] = {now = function() return clock end, to_number = function(value) return value end}
package.loaded.device = {isKindle = function() return true end}
local logs = {}
local function log(...)
    for _, value in ipairs({...}) do assert(not tostring(value):find(token, 1, true)) end
    logs[#logs + 1] = {...}
end
package.loaded.logger = {info = log, warn = log}
local firewall_calls, firewall_failure = 0, false
package.loaded.pageturner_firewall = {new = function(_, port)
    return Firewall:new(port, function()
        firewall_calls = firewall_calls + 1
        return firewall_failure and 1 or 0
    end)
end}
local menu_order = {tools = {"read_timer", "calibre", "more_tools"}, more_tools = {"httpinspector"}}
package.loaded["ui/elements/reader_menu_order"] = menu_order
local original_generate_token = Pairing.generateToken
Pairing.generateToken = function() return token end
local Plugin = dofile("pageturner.koplugin/main.lua")
local function plugin(enable_pairing)
    local reader = {document = {}, events = {}, menu = {registerToMainMenu = function() end}}
    function reader:handleEvent(event) self.events[#self.events + 1] = event end
    manager.top = reader
    local instance = Plugin:new{ui = reader, path = "pageturner.koplugin"}
    instance.readConfig = function() return {port = 8088} end
    if not enable_pairing then instance.preparePairing = function() end end
    return instance, reader
end
test("plugin starts disabled, acknowledges before dispatch and sends exactly one event", function()
    local p, reader = plugin()
    eq(p.enabled, false); eq(p.server, nil)
    assert(p:start())
    assert(p:onRequest(request()):find("202 Accepted", 1, true))
    eq(#reader.events, 0)
    assert(p:onRequest(request("/back")):find("409 Conflict", 1, true))
    manager:tick(); eq(#reader.events, 1)
    eq(reader.events[1].name, "GotoViewRel"); eq(reader.events[1].direction, 1)
    assert(p:onRequest(request("/back")):find("202 Accepted", 1, true))
    manager:tick(); eq(reader.events[2].direction, -1)
    p:stop(); eq(next(manager.queues), nil)
end)
test("approved browser preflight returns CORS permission without a page turn", function()
    local p, reader = plugin(); assert(p:start())
    local before = #logs
    local client = peer({preflight()})
    incoming = {client}; p.server:waitEvent(); manager:tick()
    eq(#reader.events, 0)
    assert(client.output:find("204 No Content", 1, true))
    assert(client.output:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    eq(logs[before + 1][1], "PageTurner: transport")
    eq(logs[before + 2][3], "request")
    assert(logs[before + 2][4]:find("method=OPTIONS", 1, true))
    eq(logs[before + 3][3], "response_status")
    eq(logs[before + 3][4], 204)
    p:stop()
end)
test("browser POST responses include CORS while auth and reader guards remain active", function()
    local p, reader = plugin(); assert(p:start())
    local unauthorized = p:onRequest(browserRequest("/next", "wrong"))
    assert(unauthorized:find("401 Unauthorized", 1, true))
    assert(unauthorized:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    local forbidden = p:onRequest(browserRequest("/next", token, "https://evil.example"))
    assert(forbidden:find("403 Forbidden", 1, true))
    assert(not forbidden:find("Access-Control-Allow-Origin", 1, true))
    manager.top = {}
    local covered = p:onRequest(browserRequest())
    assert(covered:find("409 Conflict", 1, true))
    assert(covered:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    manager.top = reader
    local accepted = p:onRequest(browserRequest())
    assert(accepted:find("202 Accepted", 1, true))
    assert(accepted:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    manager:tick(); eq(#reader.events, 1)
    p:stop()
end)
test("connection check authenticates with menus open and never queues or changes a turn", function()
    local p, reader = plugin(); assert(p:start())
    manager.top = {} -- pairing QR or menu covers the reader
    local result = p:onRequest(browserRequest("/connect"))
    assert(result:find("204 No Content", 1, true))
    assert(result:find("Access-Control-Allow-Origin: https://iamads.github.io", 1, true))
    eq(result:match("\r\n\r\n(.*)$"), "")
    eq(p.pending, nil); eq(p.sequence, 0)
    manager:tick(); eq(#reader.events, 0)
    manager.top = reader
    p:onRequest(request()); local pending = p.pending
    local sequence = p.sequence
    assert(p:onRequest(request("/connect")):find("204 No Content", 1, true))
    eq(p.pending, pending); eq(p.sequence, sequence)
    manager:tick(); eq(#reader.events, 1)
    p:stop()
    assert(p:onRequest(request("/connect")):find("503", 1, true))
end)
test("connection check retains strict authentication, method, body and origin checks", function()
    local p, reader = plugin(); assert(p:start())
    for _, case in ipairs({
        {browserRequest("/connect", "old-token"), 401},
        {"POST /connect HTTP/1.1\r\n\r\n", 401},
        {browserRequest("/connect", token, "https://evil.example"), 403},
        {request("/connect", token, "GET"), 405},
        {request("/connect", token, "POST", "Content-Length: 1\r\n"), 400},
        {request("/connect", token, "POST", "authorization: Bearer " .. token .. "\r\n"), 400},
        {request("/connect?token=" .. token), 404},
    }) do
        assert(p:onRequest(case[1]):find("HTTP/1.1 " .. case[2], 1, true))
    end
    assert(p:onRequest(preflight("/connect")):find("204 No Content", 1, true))
    assert(not p:onRequest(preflight("/connect", nil, "GET")):find("204 No Content", 1, true))
    eq(p.pending, nil); manager:tick(); eq(#reader.events, 0)
    p:stop()
end)
test("unauthorized requests and covered/absent books never turn pages", function()
    local p, reader = plugin(); assert(p:start())
    assert(p:onRequest(request(nil, "wrong")):find("401", 1, true))
    manager.top = {}; assert(p:onRequest(request()):find("409", 1, true))
    manager.top = reader; reader.document = nil
    assert(p:onRequest(request()):find("409", 1, true))
    manager:tick(); eq(#reader.events, 0); p:stop()
end)
test("stop, close, and reader changes cancel deferred commands", function()
    local p, reader = plugin(); assert(p:start())
    p:onRequest(request()); local stale = p.pending
    p:stop(); stale(); manager:tick(); eq(#reader.events, 0)
    assert(p:start()); p:onRequest(request()); manager.top = {}; manager:tick()
    eq(#reader.events, 0)
    manager.top = reader; p:onRequest(request()); p:onCloseDocument(); manager:tick()
    eq(#reader.events, 0); eq(p.enabled, false); eq(p.server, nil)
end)
test("session token survives normal suspend but rotates after close", function()
    local generated = {string.rep("b", 64), string.rep("c", 64)}
    Pairing.generateToken = function() return table.remove(generated, 1) end
    local p = plugin(); p:onResume(); eq(p.server, nil)
    assert(p:start()); p.enabled = true
    local first = p.session_token
    p:onSuspend(); eq(p.server, nil); eq(p.session_token, first)
    p:onResume(); assert(p.server); eq(p.session_token, first)
    p:onEnterStandby(); eq(p.server, nil); eq(p.session_token, first)
    p:onLeaveStandby(); assert(p.server); eq(p.session_token, first)
    p:onCloseWidget(); eq(p.session_token, nil); p:onResume(); eq(p.server, nil)
    assert(p:start()); assert(p.session_token ~= first)
    assert(p:onRequest(request(nil, first)):find("401 Unauthorized", 1, true))
    assert(p:onRequest(request("/connect", first)):find("401 Unauthorized", 1, true))
    assert(p:onRequest(request("/connect", p.session_token)):find("204 No Content", 1, true))
    p:stop()
    Pairing.generateToken = function() return token end
end)
test("bind or firewall failure leaves no live listener/queue", function()
    local p = plugin()
    local before = firewall_calls
    bind_error = "in use"; eq(p:start(), nil); eq(firewall_calls, before); bind_error = nil
    firewall_failure = true; eq(p:start(), nil); firewall_failure = false
    eq(last_listener.closed, true); eq(p.server, nil); eq(next(manager.queues), nil)
    p:stop()
end)
test("configuration requires only a valid listener port", function()
    local original = dofile
    local p = plugin()
    local configs = {{}, {port = "8088; bad"}, {port = 8088.5}, {port = 80}}
    for _, config in ipairs(configs) do
        _G.dofile = function() return config end
        local result = Plugin.readConfig(p)
        eq(result, nil)
    end
    _G.dofile = function() return {port = 8088} end
    assert(Plugin.readConfig(p))
    _G.dofile = original
end)
test("Page Turner is first in Tools without duplicates or reordering other entries", function()
    local p = plugin()
    local items = {}
    p:addToMainMenu(items); p:addToMainMenu(items)
    eq(table.concat(menu_order.tools, ","), "pageturner,read_timer,calibre,more_tools")
    eq(table.concat(menu_order.more_tools, ","), "httpinspector")
    eq(items.pageturner.sorting_hint, "tools")
    eq(items.pageturner.sub_item_table[2].enabled_func(), false)
    eq(items.pageturner.sub_item_table[3].enabled_func(), false)
end)
test("manual start prepares pairing and details refresh without exposing token", function()
    local Network = require("pageturner_network")
    local original = Network.snapshot
    local snapshots = 0
    Network.snapshot = function()
        snapshots = snapshots + 1
        return {ssid = "Bedroom", ip = "192.168.0." .. snapshots, address = "192.168.0." .. snapshots}
    end
    local p = plugin()
    local messages, updates, pairing_calls = {}, 0, 0
    p.notify = function(_, text) messages[#messages + 1] = text end
    p.preparePairing = function() pairing_calls = pairing_calls + 1 end
    local items = {}; p:addToMainMenu(items)
    local submenu = items.pageturner.sub_item_table
    local menu = {updateItems = function() updates = updates + 1 end}
    submenu[1].callback(menu)
    eq(p.enabled, true); eq(updates, 1); eq(pairing_calls, 1); eq(#messages, 0)
    eq(submenu[2].enabled_func(), true)
    submenu[2].callback(); eq(pairing_calls, 2)
    submenu[3].callback()
    assert(messages[1]:find("Wi-Fi: Bedroom\nKindle IP: 192.168.0.1\nPort: 8088", 1, true))
    assert(messages[1]:find("Local Wi-Fi: http://192.168.0.1:8088", 1, true))
    assert(not messages[1]:find(token, 1, true))
    p:onSuspend(); p:onResume(); eq(#messages, 1) -- no QR or popup on automatic resume
    submenu[1].callback(menu)
    eq(p.enabled, false); eq(#messages, 1); eq(submenu[2].enabled_func(), false)
    Network.snapshot = original
end)
test("pairing prefers matching private Serve and falls back to local Wi-Fi", function()
    local Network = require("pageturner_network")
    local original_snapshot = Network.snapshot
    local original_start = Endpoint.startServeProbe
    local original_read = Endpoint.readServeProbe
    local original_cancel = Endpoint.cancelServeProbe
    Network.snapshot = function()
        return {ssid = "Bedroom", ip = "192.168.0.8", address = "192.168.0.8"}
    end
    Endpoint.startServeProbe = function() return "/tmp/pageturner-serve-status-99.log" end
    local output = "https://kindle.example.ts.net (tailnet only)\n"
        .. "|-- / proxy http://127.0.0.1:8088\n"
    Endpoint.readServeProbe = function() return output end
    Endpoint.cancelServeProbe = function() end

    local p = plugin(true)
    local shown = {}
    p.showPairing = function(_, endpoint, route) shown[#shown + 1] = {endpoint, route} end
    assert(p:start()); p:preparePairing(); manager:tick()
    eq(shown[1][1], "https://kindle.example.ts.net"); eq(shown[1][2], "tailscale")

    output = "https://kindle.example.ts.net (tailnet only)\n"
        .. "|-- / proxy http://127.0.0.1:9999\n"
    p:preparePairing(); manager:tick()
    eq(shown[2][1], "http://192.168.0.8:8088"); eq(shown[2][2], "local")
    p:stop()
    Network.snapshot = original_snapshot
    Endpoint.startServeProbe = original_start
    Endpoint.readServeProbe = original_read
    Endpoint.cancelServeProbe = original_cancel
end)
test("network information failure cannot prevent startup or invent a usable URL", function()
    local Network = require("pageturner_network")
    local original = Network.snapshot
    Network.snapshot = function() error("unsupported platform API") end
    local p = plugin()
    local items = {}; p:addToMainMenu(items)
    items.pageturner.sub_item_table[1].callback()
    assert(p.server); eq(p.enabled, true)
    local details = p:connectionInfoText()
    assert(details:find("Wi-Fi: Unavailable", 1, true))
    assert(details:find("Port: 8088", 1, true))
    assert(not details:find("http://", 1, true))
    p:stop(); eq(p:connectionInfoText(), "Page Turner is not listening.")
    Network.snapshot = original
end)
Pairing.generateToken = original_generate_token
print("Passed " .. count .. " tests (mocked KOReader and sockets; on-device verification still required).")
