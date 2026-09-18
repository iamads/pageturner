-- Minimal, bodyless HTTP protocol. Never log raw requests (they contain a token).
local HTTP = {}
local reasons = {
    [202] = "Accepted", [400] = "Bad Request", [401] = "Unauthorized",
    [404] = "Not Found", [405] = "Method Not Allowed", [409] = "Conflict",
    [431] = "Request Header Fields Too Large", [500] = "Internal Server Error",
    [503] = "Service Unavailable",
}

function HTTP.response(status, message)
    local body = message .. "\n"
    return "HTTP/1.1 " .. status .. " " .. reasons[status] .. "\r\n"
        .. "Content-Type: text/plain; charset=utf-8\r\n"
        .. "Content-Length: " .. #body .. "\r\n"
        .. "Connection: close\r\nCache-Control: no-store\r\n"
        .. (status == 405 and "Allow: POST\r\n" or "")
        .. "\r\n" .. body
end

-- Returns direction (+1/-1), or nil, status, safe error message.
function HTTP.command(request, token)
    local head, extra = request:match("^(.-)\r\n\r\n(.*)$")
    if not head or extra ~= "" then
        return nil, 400, "Expected one bodyless request"
    end
    local first, headers = head:match("^([^\r\n]+)\r\n(.*)$")
    if not first then first, headers = head, "" end
    local method, path, version = first:match("^(%u+) (/[^ ]*) HTTP/(1%.[01])$")
    if not version then return nil, 400, "Malformed request line" end
    local values = {}
    if headers ~= "" then
        for line in (headers .. "\r\n"):gmatch("(.-)\r\n") do
            local name, value = line:match("^([%w%-]+):[ \t]*(.-)[ \t]*$")
            if not name or value:find("[%c]") then
                return nil, 400, "Malformed header"
            end
            name = name:lower()
            if values[name] then return nil, 400, "Duplicate header" end
            values[name] = value
        end
    end
    if not token or token == "" or values.authorization ~= "Bearer " .. token then
        return nil, 401, "Missing or invalid bearer token"
    end
    if method ~= "POST" then return nil, 405, "Use POST" end
    if values["transfer-encoding"] or values.expect
        or (values["content-length"] and values["content-length"] ~= "0") then
        return nil, 400, "Request bodies are not supported"
    end
    if path == "/next" then return 1 end
    if path == "/back" then return -1 end
    return nil, 404, "Use /next or /back"
end

return HTTP
