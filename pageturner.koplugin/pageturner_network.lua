-- Read-only network details. No Wi-Fi scans, connection attempts, DNS or pings.
local Network = {}

function Network.getIPv4(interface)
    if type(interface) ~= "string" or interface == "" then return nil end
    local ffi = require("ffi")
    local bit = require("bit")
    require("ffi/posix_h") -- KOReader's platform-specific getifaddrs definitions
    local C = ffi.C
    local addresses = ffi.new("struct ifaddrs *[1]")
    if C.getifaddrs(addresses) ~= 0 then return nil end
    local ok, ip = pcall(function()
        local entry = addresses[0]
        while entry ~= nil do
            if entry.ifa_addr ~= nil and entry.ifa_name ~= nil
                and ffi.string(entry.ifa_name) == interface
                and bit.band(entry.ifa_flags, C.IFF_UP) ~= 0
                and bit.band(entry.ifa_flags, C.IFF_LOOPBACK) == 0
                and entry.ifa_addr.sa_family == C.AF_INET then
                local host = ffi.new("char[?]", C.NI_MAXHOST)
                if C.getnameinfo(entry.ifa_addr, ffi.sizeof("struct sockaddr_in"),
                    host, C.NI_MAXHOST, nil, 0, C.NI_NUMERICHOST) == 0 then
                    local value = ffi.string(host)
                    if value ~= "0.0.0.0" and not value:match("^127%.") then return value end
                end
            end
            entry = entry.ifa_next
        end
    end)
    C.freeifaddrs(addresses[0])
    if ok then return ip end
end

function Network.snapshot()
    local result = {ssid = "Unavailable", ip = "Unavailable (no Wi-Fi IPv4 address)"}
    local ok, manager = pcall(require, "ui/network/manager")
    if not ok then return result end
    local has_state, wifi_on = pcall(function() return manager:isWifiOn() end)
    if has_state and wifi_on == false then result.ssid = "Off"; return result end
    local has_interface, interface = pcall(function() return manager:getNetworkInterfaceName() end)
    local has_ip, ip
    if has_interface then has_ip, ip = pcall(Network.getIPv4, interface) end
    if has_ip and ip then result.ip = ip; result.address = ip end
    local has_network, current = pcall(function() return manager:getCurrentNetwork() end)
    if has_network and type(current) == "table" and type(current.ssid) == "string" and current.ssid ~= "" then
        -- An SSID is an arbitrary byte string; keep it safe for KOReader's text UI.
        local valid, util = pcall(require, "util")
        if valid then result.ssid = util.fixUtf8(current.ssid, "�"):gsub("[%c]", " ") end
    end
    return result
end

return Network
