-- Pairing token and payload helpers. Tokens exist only for one manual listener session.
local Pairing = {}

local function readRandomBytes(count)
    local file = io.open("/dev/urandom", "rb")
    if not file then return nil end
    local bytes = file:read(count)
    file:close()
    if type(bytes) ~= "string" or #bytes ~= count then return nil end
    return bytes
end

function Pairing.generateToken(reader)
    local bytes = (reader or readRandomBytes)(32)
    if type(bytes) ~= "string" or #bytes ~= 32 then
        return nil, "Could not obtain secure random bytes for pairing."
    end
    return (bytes:gsub(".", function(byte)
        return string.format("%02x", string.byte(byte))
    end))
end

function Pairing.payload(endpoint, token)
    local authority = type(endpoint) == "string" and endpoint:match("^https?://([^/]+)$")
    local host, port
    if authority then host, port = authority:match("^([A-Za-z0-9%.%-]+):?(%d*)$") end
    if not host or (port ~= "" and (tonumber(port) < 1 or tonumber(port) > 65535)) then
        return nil, "Invalid pairing endpoint."
    end
    if type(token) ~= "string" or not token:match("^[A-Za-z0-9_-]+$")
        or #token < 32 or #token > 128 then
        return nil, "Invalid pairing token."
    end
    -- Both values are deliberately restricted to JSON-safe ASCII above.
    return string.format('{"version":1,"endpoint":"%s","token":"%s"}', endpoint, token)
end

return Pairing
