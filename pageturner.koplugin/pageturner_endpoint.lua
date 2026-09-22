-- Resolve the preferred pairing endpoint without changing network state.
local Endpoint = {}

local BASE = "/mnt/us/extensions/pageturner-tunnel"
local CLI = BASE .. "/bin/tailscale"
local SOCKET = "/tmp/pageturner-tailscaled.sock"
local RESULT_PREFIX = "/tmp/pageturner-serve-status-"

function Endpoint.localUrl(network, port)
    if type(network) ~= "table" or type(network.address) ~= "string" then return nil end
    if type(port) ~= "number" or port ~= math.floor(port) or port < 1 or port > 65535 then return nil end
    return "http://" .. network.address .. ":" .. port
end

function Endpoint.parseServeStatus(output, port)
    if type(output) ~= "string" or type(port) ~= "number" then return nil end
    local endpoint
    for line in output:gmatch("[^\r\n]+") do
        local candidate = line:match("^(https://[A-Za-z0-9%.%-]+%.ts%.net)/?")
        if candidate then endpoint = candidate end
    end
    if not endpoint then return nil end
    local backend = "proxy http://127.0.0.1:" .. port
    if not output:find(backend, 1, true) then return nil end
    return endpoint
end

function Endpoint.startServeProbe(id, execute)
    if type(id) ~= "number" or id ~= math.floor(id) or id < 1 then return nil end
    local result = RESULT_PREFIX .. id .. ".log"
    local temporary = result .. ".tmp"
    os.remove(result)
    os.remove(temporary)
    local command = "( ( if [ -S '" .. SOCKET .. "' ] && [ -x '" .. CLI
        .. "' ]; then timeout -t 3 '" .. CLI .. "' --socket='" .. SOCKET
        .. "' serve status; fi ) > '" .. temporary .. "' 2>/dev/null; mv '"
        .. temporary .. "' '" .. result .. "' ) &"
    local status = (execute or os.execute)(command)
    if status ~= 0 and status ~= true then
        os.remove(temporary)
        return nil
    end
    return result
end

-- Returns nil while pending. Once complete, returns the output (possibly empty)
-- and removes the transient result file.
function Endpoint.readServeProbe(path)
    if type(path) ~= "string" or not path:match("^/tmp/pageturner%-serve%-status%-%d+%.log$") then
        return nil
    end
    local file = io.open(path, "rb")
    if not file then return nil end
    local output = file:read("*a") or ""
    file:close()
    os.remove(path)
    return output
end

function Endpoint.cancelServeProbe(path)
    if type(path) == "string" and path:match("^/tmp/pageturner%-serve%-status%-%d+%.log$") then
        os.remove(path)
        os.remove(path .. ".tmp")
    end
end

return Endpoint
