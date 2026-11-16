-- Sharp, monochrome icon tap target shared by the dashboard header, the
-- bottom navigation and the in-card actions. No ripples, no rounded corners.
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local TapIcon = InputContainer:extend{
    icon = nil,
    file = nil,
    width = nil,
    height = nil,
    on_tap = nil,
    show_parent = nil,
}

function TapIcon:init()
    self.show_parent = self.show_parent or self
    self[1] = IconWidget:new{
        icon = self.icon,
        file = self.file,
        width = self.width,
        height = self.height,
    }
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapIcon = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function TapIcon:onTapIcon()
    UIManager:setDirty(self.show_parent, "ui")
    if type(self.on_tap) == "function" then self.on_tap() end
    return true
end

return TapIcon
