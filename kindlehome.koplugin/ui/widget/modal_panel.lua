local Device = require("device")
local CenterContainer = require("ui/widget/container/centercontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local Screen = Device.screen

local ModalPanel = InputContainer:extend{
    panel = nil,
}

function ModalPanel:init()
    self.dimen = Screen:getSize()
    self.ges_events.TapOutside = {
        GestureRange:new{ ges = "tap", range = self.dimen },
    }
end

function ModalPanel:set_panel(panel)
    self.panel = panel
    self[1] = CenterContainer:new{
        dimen = self.dimen,
        panel,
    }
end

function ModalPanel:onTapOutside(arg, ges)
    if self.panel and self.panel.dimen and ges.pos
        and ges.pos:notIntersectWith(self.panel.dimen) then
        self:on_close()
    end
    return true
end

function ModalPanel:on_close()
end

return ModalPanel
