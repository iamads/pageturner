-- Minimal, bodyless HTTP protocol. Never log raw requests (they contain a token).
local HTTP = {}
local ALLOWED_ORIGIN = "https://iamads.github.io"
local reasons = {
    [202] = "Accepted", [204] = "No Content", [400] = "Bad Request",
    [401] = "Unauthorized", [403] = "Forbidden", [404] = "Not Found",
    [405] = "Method Not Allowed", [409] = "Conflict",
    [431] = "Request Header Fields Too Large", [500] = "Internal Server Error",
    [503] = "Service Unavailable",
}

-- options.cors exposes a response only to the one approved browser origin.
-- options.preflight adds the fixed permission grant; no caller-supplied headers.
function HTTP.response(status, message, options)
    options = options or {}
    local body = status == 204 and "" or message .. "\n"
    local headers = "HTTP/1.1 " .. status .. " " .. reasons[status] .. "\r\n"
        .. (status == 204 and "" or "Content-Type: text/plain; charset=utf-8\r\n")
        .. "Content-Length: " .. #body .. "\r\n"
        .. "Connection: close\r\nCache-Control: no-store\r\n"
        .. (status == 405 and "Allow: POST, OPTIONS\r\n" or "")
    if options.cors then
        headers = headers
            .. "Access-Control-Allow-Origin: " .. ALLOWED_ORIGIN .. "\r\n"
            .. "Vary: Origin\r\n"
    end
    if options.preflight then
        headers = headers
            .. "Access-Control-Allow-Methods: POST\r\n"
            .. "Access-Control-Allow-Headers: Authorization\r\n"
            .. "Access-Control-Max-Age: 600\r\n"
        if options.private_network then
            headers = headers .. "Access-Control-Allow-Private-Network: true\r\n"
        end
    end
    return headers .. "\r\n" .. body
end

local function parse(request)
    local head, extra = request:match("^(.-)\r\n\r\n(.*)$")
    if not head or extra ~= "" then
        return nil, 400, "Expected one bodyless request"
    end
    local first, header_lines = head:match("^([^\r\n]+)\r\n(.*)$")
    if not first then first, header_lines = head, "" end
    local method, path, version = first:match("^(%u+) (/[^ ]*) HTTP/(1%.[01])$")
    if not version then return nil, 400, "Malformed request line" end
    local headers = {}
    if header_lines ~= "" then
        for line in (header_lines .. "\r\n"):gmatch("(.-)\r\n") do
            local name, value = line:match("^([%w%-]+):[ \t]*(.-)[ \t]*$")
            if not name or value:find("[%c]") then
                return nil, 400, "Malformed header"
            end
            name = name:lower()
            if headers[name] then return nil, 400, "Duplicate header" end
            headers[name] = value
        end
    end
    if headers["transfer-encoding"] or headers.expect
        or (headers["content-length"] and headers["content-length"] ~= "0") then
        return nil, 400, "Request bodies are not supported"
    end
    return {method = method, path = path, headers = headers}
end

local function allowedRoute(path)
    return path == "/next" or path == "/back" or path == "/connect"
end

local function allowedRequestedHeaders(value)
    if type(value) ~= "string" then return false end
    local found = false
    for header in (value .. ","):gmatch("([^,]*),") do
        header = header:match("^[ \t]*(.-)[ \t]*$"):lower()
        if header == "" or header ~= "authorization" or found then return false end
        found = true
    end
    return found
end

-- Returns a complete response for OPTIONS, or nil for non-OPTIONS requests.
-- Preflight grants browser permission to attempt an authenticated POST; it does
-- not authenticate, enqueue, or dispatch a page turn.
function HTTP.preflight(request)
    local parsed, status, message = parse(request)
    if not parsed then
        -- Only recognizable OPTIONS requests belong to this handler. Malformed
        -- requests continue through command() for the existing safe 400 path.
        if request:match("^OPTIONS ") then return HTTP.response(status, message) end
        return nil
    end
    if parsed.method ~= "OPTIONS" then return nil end
    local headers = parsed.headers
    if headers.origin ~= ALLOWED_ORIGIN then
        return HTTP.response(403, "Origin is not allowed")
    end
    local cors = {cors = true}
    if not allowedRoute(parsed.path) then
        return HTTP.response(404, "Use /next, /back or /connect", cors)
    end
    if headers["access-control-request-method"] ~= "POST" then
        return HTTP.response(405, "Only POST may be requested", cors)
    end
    if not allowedRequestedHeaders(headers["access-control-request-headers"]) then
        return HTTP.response(400, "Only Authorization may be requested", cors)
    end
    local private_network = headers["access-control-request-private-network"]
    if private_network ~= nil and private_network ~= "true" then
        return HTTP.response(400, "Invalid private-network request", cors)
    end
    return HTTP.response(204, "", {
        cors = true,
        preflight = true,
        private_network = private_network == "true",
    })
end

-- Diagnostics only, never used for authorization or routing. Emit fixed labels,
-- not user-supplied text: even a token in a path, Origin, or malformed header
-- must not reach logs. Values on duplicate headers are deliberately ambiguous.
function HTTP.requestSummary(request)
    local head = request:sub(1, 4096):match("^(.-)\r\n\r\n") or ""
    local first = head:match("^([^\r\n]+)") or ""
    local method, path = first:match("^(%u+) (/[^ ]*) HTTP/1%.[01]$")
    local methods = {POST = true, OPTIONS = true, GET = true, HEAD = true}
    method = methods[method] and method or "other"
    path = allowedRoute(path) and path or "other"
    local headers = {}
    for line in head:gmatch("\r\n([^\r\n]+)") do
        local name, value = line:match("^([%w%-]+):[ \t]*(.-)[ \t]*$")
        if name then
            name = name:lower()
            if headers[name] ~= nil then headers[name] = false
            else headers[name] = value end
        end
    end
    local function label(name, expected, matched)
        local value = headers[name]
        if value == nil then return "absent" end
        return value == expected and matched or "other"
    end
    local requested_headers = headers["access-control-request-headers"]
    if type(requested_headers) == "string" then
        headers["access-control-request-headers"] = requested_headers:lower()
    end
    return "method=" .. method .. " route=" .. path
        .. " origin=" .. label("origin", ALLOWED_ORIGIN, "pages")
        .. " auth=" .. (headers.authorization ~= nil and "present" or "absent")
        .. " requested_method=" .. label("access-control-request-method", "POST", "POST")
        .. " requested_headers=" .. label("access-control-request-headers", "authorization", "authorization")
        .. " private_network=" .. label("access-control-request-private-network", "true", "true")
end

-- Returns direction (+1/-1), or nil, status, safe message, cors_allowed.
-- /connect returns nil, 204 before reader/queue guards: it authenticates only,
-- never creates a navigation direction or touches pending page turns.
function HTTP.command(request, token)
    local parsed, status, message = parse(request)
    if not parsed then return nil, status, message, false end
    local headers = parsed.headers
    local cors = headers.origin == ALLOWED_ORIGIN
    if headers.origin and not cors then
        return nil, 403, "Origin is not allowed", false
    end
    if not token or token == "" or headers.authorization ~= "Bearer " .. token then
        return nil, 401, "Missing or invalid bearer token", cors
    end
    if parsed.method ~= "POST" then return nil, 405, "Use POST", cors end
    if parsed.path == "/next" then return 1, nil, nil, cors end
    if parsed.path == "/back" then return -1, nil, nil, cors end
    if parsed.path == "/connect" then return nil, 204, "", cors end
    return nil, 404, "Use /next, /back or /connect", cors
end

return HTTP
