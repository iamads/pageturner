-- Full-screen pairing QR with the selected route and endpoint shown underneath.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local QRWidget = require("ui/widget/qrwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Input = Device.input
local Screen = Device.screen

local PairingMessage = InputContainer:extend{
    modal = true,
    payload = nil,
    endpoint = nil,
    route = nil,
    dismiss_callback = nil,
}

function PairingMessage:init()
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                },
            },
        }
    end

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local outer_padding = Screen:scaleBySize(18)
    local qr_size = math.floor(math.min(screen_width * 0.78, screen_height * 0.62))
    local text_width = screen_width - 4 * outer_padding
    local details = (self.route == "tailscale" and "Private Tailscale" or "Local Wi-Fi")
        .. "\n" .. self.endpoint .. "\nScan in Page Turner, then tap to close"

    local content = VerticalGroup:new{
        align = "center",
        QRWidget:new{
            text = self.payload,
            width = qr_size,
            height = qr_size,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(12) },
        TextBoxWidget:new{
            text = details,
            face = Font:getFace("cfont", 20),
            width = text_width,
            alignment = "center",
        },
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        padding = outer_padding,
        content,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }
end

function PairingMessage:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function PairingMessage:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self[1][1].dimen
    end)
    if self.dismiss_callback then
        self.dismiss_callback()
        self.dismiss_callback = nil
    end
end

function PairingMessage:onTapClose()
    UIManager:close(self)
    return true
end
PairingMessage.onAnyKeyPressed = PairingMessage.onTapClose

return PairingMessage
