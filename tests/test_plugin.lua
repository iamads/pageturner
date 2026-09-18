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
local manager = {tasks = {}, queues = {}}
function manager:nextTick(fn) self.tasks[#self.tasks + 1] = fn end
function manager:unschedule(fn)
    for i = #self.tasks, 1, -1 do if self.tasks[i] == fn then table.remove(self.tasks, i) end end
end
function manager:insertZMQ(server) self.queues[server] = true end
function manager:removeZMQ(server) self.queues[server] = nil end
function manager:getTopmostVisibleWidget() return self.top end
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
local Plugin = dofile("pageturner.koplugin/main.lua")
local function plugin()
    local reader = {document = {}, events = {}, menu = {registerToMainMenu = function() end}}
    function reader:handleEvent(event) self.events[#self.events + 1] = event end
    manager.top = reader
    local instance = Plugin:new{ui = reader, path = "pageturner.koplugin"}
    instance.readConfig = function() return {port = 8088, token = token} end
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
test("suspend cleans up and normal resume only restores an enabled listener", function()
    local p = plugin(); p:onResume(); eq(p.server, nil)
    assert(p:start()); p.enabled = true; p:onSuspend()
    eq(p.server, nil); eq(p.enabled, true); eq(p.firewall, nil)
    p:onResume(); assert(p.server)
    p:onEnterStandby(); eq(p.server, nil)
    p:onLeaveStandby(); assert(p.server)
    p:onCloseWidget(); p:onResume(); eq(p.server, nil)
end)
test("bind or firewall failure leaves no live listener/queue", function()
    local p = plugin()
    local before = firewall_calls
    bind_error = "in use"; eq(p:start(), nil); eq(firewall_calls, before); bind_error = nil
    firewall_failure = true; eq(p:start(), nil); firewall_failure = false
    eq(last_listener.closed, true); eq(p.server, nil); eq(next(manager.queues), nil)
    p:stop()
end)
test("configuration rejects missing token and invalid port without exposing secrets", function()
    local original = dofile
    local p = plugin()
    local configs = {{}, {port = 8088, token = ""}, {port = "8088; bad", token = token}, {port = 8088.5, token = token}}
    for _, config in ipairs(configs) do
        _G.dofile = function() return config end
        local result, err = Plugin.readConfig(p)
        eq(result, nil); assert(not err:find(token, 1, true))
    end
    _G.dofile = function() return {port = 8088, token = token} end
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
end)
test("manual start shows fresh Wi-Fi/IP/port; details refresh without exposing token", function()
    local Network = require("pageturner_network")
    local original = Network.snapshot
    local snapshots = 0
    Network.snapshot = function()
        snapshots = snapshots + 1
        return {ssid = "Bedroom", ip = "192.168.0." .. snapshots, address = "192.168.0." .. snapshots}
    end
    local p = plugin()
    local messages, updates = {}, 0
    p.notify = function(_, text) messages[#messages + 1] = text end
    local items = {}; p:addToMainMenu(items)
    local submenu = items.pageturner.sub_item_table
    local menu = {updateItems = function() updates = updates + 1 end}
    submenu[1].callback(menu)
    eq(p.enabled, true); eq(updates, 1); eq(#messages, 1)
    assert(messages[1]:find("Wi-Fi: Bedroom\nKindle IP: 192.168.0.1\nPort: 8088", 1, true))
    assert(messages[1]:find("http://192.168.0.1:8088", 1, true))
    assert(not messages[1]:find(token, 1, true))
    eq(submenu[2].enabled_func(), true)
    submenu[2].callback()
    assert(messages[2]:find("Kindle IP: 192.168.0.2", 1, true))
    p:onSuspend(); p:onResume(); eq(#messages, 2) -- no popup on automatic resume
    submenu[1].callback(menu)
    eq(p.enabled, false); eq(#messages, 2); eq(submenu[2].enabled_func(), false)
    Network.snapshot = original
end)
test("network information failure cannot prevent startup or invent a usable URL", function()
    local Network = require("pageturner_network")
    local original = Network.snapshot
    Network.snapshot = function() error("unsupported platform API") end
    local p = plugin()
    local messages = {}
    p.notify = function(_, text) messages[#messages + 1] = text end
    local items = {}; p:addToMainMenu(items)
    items.pageturner.sub_item_table[1].callback()
    assert(p.server); eq(p.enabled, true)
    assert(messages[1]:find("Wi-Fi: Unavailable", 1, true))
    assert(messages[1]:find("Port: 8088", 1, true))
    assert(not messages[1]:find("http://", 1, true))
    p:stop(); eq(p:connectionInfoText(), "Page Turner is not listening.")
    Network.snapshot = original
end)
print("Passed " .. count .. " tests (mocked KOReader and sockets; on-device verification still required).")
