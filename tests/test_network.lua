-- Read-only network lookup tests; no network connections or device changes.
-- Run from the project root: luajit tests/test_network.lua
package.path = "pageturner.koplugin/?.lua;" .. package.path
local Network = require("pageturner_network")
local count = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn) fn(); count = count + 1; print("ok " .. count .. " - " .. name) end

-- getifaddrs double: assert interface selection, IPv4 filtering and cleanup.
local entries, freed, lookup_failure, conversion_failure, conversion_throws
local C = {IFF_UP = 1, IFF_LOOPBACK = 8, AF_INET = 2, NI_MAXHOST = 1025, NI_NUMERICHOST = 1}
function C.getifaddrs(out)
    if lookup_failure then return -1 end
    out[0] = entries
    return 0
end
function C.freeifaddrs(value) eq(value, entries); freed = freed + 1 end
function C.getnameinfo(address, _, host)
    if conversion_throws then error("unavailable symbol") end
    if conversion_failure then return -1 end
    host.value = address.ip
    return 0
end
package.loaded.ffi = {
    C = C,
    new = function() return {} end,
    sizeof = function() return 16 end,
    string = function(value) return type(value) == "table" and value.value or value end,
}
package.loaded["ffi/posix_h"] = {}
local function entry(name, ip, family, flags)
    return {ifa_name = name, ifa_addr = {sa_family = family or 2, ip = ip}, ifa_flags = flags or 1}
end
local function interfaces(list)
    entries = list[1]
    for i, value in ipairs(list) do value.ifa_next = list[i + 1] end
    freed = 0; lookup_failure = false; conversion_failure = false; conversion_throws = false
end

test("selects Wi-Fi IPv4, not USB, loopback, downed interface or IPv6", function()
    interfaces({entry("lo", "127.0.0.1", 2, 9), entry("usb0", "192.168.15.244"),
        entry("wlan0", "192.168.0.2", 2, 0), entry("wlan0", "fe80::1", 10),
        entry("wlan0", "192.168.0.113")})
    eq(Network.getIPv4("wlan0"), "192.168.0.113"); eq(freed, 1)
end)
test("no matching IPv4 or null address returns unavailable and releases list", function()
    interfaces({{ifa_name = "wlan0", ifa_flags = 1}, entry("usb0", "192.168.15.244")})
    eq(Network.getIPv4("wlan0"), nil); eq(freed, 1)
end)
test("does not present wildcard or loopback addresses as a connection target", function()
    interfaces({entry("wlan0", "0.0.0.0"), entry("wlan0", "127.0.0.2")})
    eq(Network.getIPv4("wlan0"), nil); eq(freed, 1)
end)
test("failed enumeration and invalid interface fail safely", function()
    interfaces({}); lookup_failure = true
    eq(Network.getIPv4("wlan0"), nil); eq(freed, 0)
    eq(Network.getIPv4(nil), nil); eq(Network.getIPv4(""), nil)
end)
test("failed conversion and exceptions always release allocated list", function()
    interfaces({entry("wlan0", "192.168.0.113")}); conversion_failure = true
    eq(Network.getIPv4("wlan0"), nil); eq(freed, 1)
    conversion_failure = false; conversion_throws = true
    eq(Network.getIPv4("wlan0"), nil); eq(freed, 2)
end)

local ssid, wifi_on, current_throws, interface_throws
package.loaded["ui/network/manager"] = {
    isWifiOn = function() return wifi_on end,
    getCurrentNetwork = function()
        if current_throws then error("unsupported") end
        return {ssid = ssid}
    end,
    getNetworkInterfaceName = function()
        if interface_throws then error("unsupported") end
        return "wlan0"
    end,
    turnOnWifi = function() error("must not enable Wi-Fi") end,
    getNetworkList = function() error("must not scan") end,
    isOnline = function() error("must not probe the internet") end,
}
package.loaded.util = {fixUtf8 = function(value, replacement) return value:gsub("\255", replacement) end}
local function connected()
    interfaces({entry("wlan0", "192.168.0.113")})
    ssid = "Bedroom Wi-Fi"; wifi_on = true; current_throws = false; interface_throws = false
end
test("snapshot provides current SSID and matching Wi-Fi address without mutations", function()
    connected()
    local result = Network.snapshot()
    eq(result.ssid, "Bedroom Wi-Fi"); eq(result.ip, "192.168.0.113"); eq(result.address, result.ip)
    -- A subsequent lookup must not reuse a cached IP or name.
    ssid = "Other Wi-Fi"; interfaces({entry("wlan0", "192.168.1.8")})
    result = Network.snapshot()
    eq(result.ssid, "Other Wi-Fi"); eq(result.address, "192.168.1.8")
end)
test("Wi-Fi off does not show stale SSID/IP or enumerate interfaces", function()
    connected(); wifi_on = false
    local result = Network.snapshot()
    eq(result.ssid, "Off"); eq(result.address, nil); eq(freed, 0)
end)
test("missing SSID or platform APIs produce explicit unavailable fields", function()
    connected(); ssid = ""
    eq(Network.snapshot().ssid, "Unavailable")
    current_throws = true; interface_throws = true
    local result = Network.snapshot()
    eq(result.ssid, "Unavailable"); eq(result.address, nil)
    assert(result.ip:find("Unavailable", 1, true))
end)
test("SSID control characters and invalid UTF-8 are safe for display", function()
    connected(); ssid = "Bed\nroom\t\255"
    eq(Network.snapshot().ssid, "Bed room �")
end)
print("Passed " .. count .. " network tests (mocked OS and KOReader APIs).")
