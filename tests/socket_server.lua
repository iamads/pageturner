-- Real LuaSocket transport harness, not a KOReader/device emulator.
package.path = "pageturner.koplugin/?.lua;" .. package.path
local socket = require("socket")
local HTTP = require("pageturner_http")
local Server = require("pageturner_server")
local count = 0
local server = Server:new{
    port = 0,
    on_request = function(request)
        local direction, status, message = HTTP.command(request, string.rep("a", 48))
        if not direction then return HTTP.response(status, message) end
        count = count + 1
        return HTTP.response(202, "accepted " .. (direction == 1 and "next" or "back") .. " request=" .. count)
    end,
}
assert(server:start())
local _, port = server.listener:getsockname()
io.write(port .. "\n"); io.flush()
local deadline = socket.gettime() + 30
while socket.gettime() < deadline do
    server:waitEvent()
    socket.sleep(0.01)
end
server:stop()
