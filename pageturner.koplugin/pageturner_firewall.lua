-- A private chain lets us remove only our own rules, never someone else's.
local Firewall = {}
Firewall.__index = Firewall
local CHAIN = "KR_PAGETURNER"

function Firewall:new(port, execute)
    assert(type(port) == "number" and port == math.floor(port) and port >= 1024 and port <= 65535)
    return setmetatable({port = port, execute = execute or os.execute, undo = {}}, self)
end

function Firewall:run(args)
    local result = self.execute("iptables " .. args)
    return result == 0 or result == true
end

function Firewall:close()
    local remaining = {}
    for i = #self.undo, 1, -1 do
        if not self:run(self.undo[i]) then
            table.insert(remaining, 1, self.undo[i])
        end
    end
    self.undo = remaining
    return #remaining == 0
end

function Firewall:open()
    local input = "INPUT -p tcp --dport " .. self.port .. " -j " .. CHAIN
    local output = "OUTPUT -p tcp --sport " .. self.port .. " -j " .. CHAIN
    local operations = {
        {"-N " .. CHAIN, "-X " .. CHAIN},
        {"-A " .. CHAIN .. " -j ACCEPT", "-D " .. CHAIN .. " -j ACCEPT"},
        {"-A " .. input, "-D " .. input},
        {"-A " .. output, "-D " .. output},
    }
    for _, operation in ipairs(operations) do
        if not self:run(operation[1]) then
            self:close()
            return nil, "Could not install Page Turner firewall rules (check crash.log)."
        end
        self.undo[#self.undo + 1] = operation[2]
    end
    return true
end

return Firewall
