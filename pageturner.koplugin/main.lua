local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local time = require("ui/time")
local HTTP = require("pageturner_http")
local Server = require("pageturner_server")
local Firewall = require("pageturner_firewall")

local PageTurner = WidgetContainer:extend{
    name = "pageturner",
    is_doc_only = true,
}

function PageTurner:init()
    self.enabled = false -- opt-in per open book; never persist or autostart
    self.sequence = 0
    self.ui.menu:registerToMainMenu(self)
end

function PageTurner:notify(message)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = message })
end

function PageTurner:readConfig()
    local ok, config = pcall(dofile, self.path .. "/config.lua")
    if not ok or type(config) ~= "table" then
        return nil, "Create pageturner.koplugin/config.lua first. See the Page Turner README."
    end
    if type(config.token) ~= "string" or #config.token < 32 or #config.token > 128
        or not config.token:match("^[%w_-]+$") then
        return nil, "Set a random 32–128 character token (letters, digits, - or _) in config.lua."
    end
    if type(config.port) ~= "number" or config.port ~= math.floor(config.port)
        or config.port < 1024 or config.port > 65535 then
        return nil, "Set an integer port between 1024 and 65535 in config.lua."
    end
    return config
end

function PageTurner:start()
    if self.server then return true end
    -- Retry any previous failed cleanup before adding new rules.
    if self.firewall then
        if not self.firewall:close() then return nil, "Previous firewall cleanup failed; see crash.log." end
        self.firewall = nil
    end
    local config, err = self:readConfig()
    if not config then return nil, err end
    local server = Server:new{
        port = config.port,
        now = function() return time.to_number(time.now()) end,
        on_request = function(request) return self:onRequest(request) end,
    }
    local ok
    ok, err = server:start()
    if not ok then return nil, "Could not listen on port " .. config.port .. ": " .. tostring(err) end
    -- Bind first, so a conflicting listener cannot leave open firewall rules.
    if Device:isKindle() then
        self.firewall = Firewall:new(config.port)
        ok, err = self.firewall:open()
        if not ok then
            server:stop()
            return nil, err
        end
    end
    self.config = config
    self.server = server
    UIManager:insertZMQ(server)
    logger.info("PageTurner: listening on port", config.port)
    return true
end

function PageTurner:stop()
    -- Invalidate deferred commands before releasing resources.
    if self.pending then UIManager:unschedule(self.pending); self.pending = nil end
    if self.server then
        UIManager:removeZMQ(self.server)
        self.server:stop()
        self.server = nil
        logger.info("PageTurner: listener stopped")
    end
    if self.firewall then
        if self.firewall:close() then
            self.firewall = nil
        else
            logger.warn("PageTurner: firewall cleanup failed; inspect KR_PAGETURNER rules")
        end
    end
    self.config = nil
end

function PageTurner:readerReady()
    return self.ui.document ~= nil and not self.ui.tearing_down
        and UIManager:getTopmostVisibleWidget() == self.ui
end

function PageTurner:onRequest(request)
    if not self.server or not self.config then return HTTP.response(503, "Listener stopped") end
    local direction, status, message = HTTP.command(request, self.config.token)
    if not direction then return HTTP.response(status, message) end
    if not self:readerReady() then return HTTP.response(409, "Open a book and close menus/dialogs first") end
    if self.pending then return HTTP.response(409, "A page turn is already pending") end

    self.sequence = self.sequence + 1
    local id = self.sequence
    local server = self.server
    local accepted_at = time.now()
    local command = direction == 1 and "next" or "back"
    local pending
    pending = function()
        if self.pending ~= pending then return end
        self.pending = nil
        if self.server ~= server or not self:readerReady() then
            logger.info("PageTurner: cancelled request", id, "reader no longer active")
            return
        end
        -- Use the reader's existing event, for both EPUB and PDF navigation.
        -- Do not emit InputEvent or change standby/suspend/Wi-Fi settings.
        local ok = pcall(function() self.ui:handleEvent(Event:new("GotoViewRel", direction)) end)
        if ok then
            logger.info("PageTurner: dispatched", id, command,
                "accept_to_handler_return_ms", time.to_number(time.now() - accepted_at) * 1000)
        else
            logger.warn("PageTurner: navigation failed for request", id)
        end
    end
    self.pending = pending
    UIManager:nextTick(pending)
    logger.info("PageTurner: accepted", id, command)
    return HTTP.response(202, "accepted " .. command .. " request=" .. id)
end

function PageTurner:addToMainMenu(menu_items)
    menu_items.pageturner = {
        text = "Page Turner (HTTP)",
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text_func = function()
                    return self.enabled and "Stop Page Turner" or "Start Page Turner"
                end,
                keep_menu_open = true,
                callback = function(menu)
                    if self.enabled then
                        self.enabled = false
                        self:stop()
                    else
                        local ok, err = self:start()
                        self.enabled = ok == true
                        if not ok then self:notify(err) end
                    end
                    if menu then menu:updateItems() end
                end,
            },
            {
                text_func = function()
                    return self.server and ("Listening on port " .. self.config.port) or "Not listening"
                end,
                enabled = false,
            },
        },
    }
end

-- Mirror lifecycle events without requesting/preventing sleep or enabling Wi-Fi.
-- The selected listener resumes only if KOReader itself resumes normally.
function PageTurner:onSuspend() self:stop() end
function PageTurner:onEnterStandby() self:stop() end
function PageTurner:onResume()
    if self.enabled and not self.server then
        local ok, err = self:start()
        if not ok then
            self.enabled = false
            logger.warn("PageTurner: resume failed", err)
        end
    end
end
function PageTurner:onLeaveStandby() self:onResume() end
function PageTurner:onCloseDocument() self.enabled = false; self:stop() end
function PageTurner:onCloseWidget() self.enabled = false; self:stop() end
function PageTurner:onExit() self.enabled = false; self:stop() end

return PageTurner
