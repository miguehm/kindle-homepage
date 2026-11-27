-- SPDX-License-Identifier: MIT
-- Full-width native tap row with bottom hairline handled by the caller.
-- The whole row inverts while its action runs (see press_feedback.lua).
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local PressFeedback = require("ui/widget/press_feedback")

local TapRow = InputContainer:extend{
    content_group = nil,
    on_tap = nil,
    show_parent = nil,
}

function TapRow:init()
    self.show_parent = self.show_parent or self
    self[1] = self.content_group
    local size = self.content_group:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function TapRow:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    PressFeedback.paint(self, bb, x, y)
end

function TapRow:onTapRow()
    if type(self.on_tap) ~= "function" then return true end
    return PressFeedback.run(self, self.on_tap)
end

return TapRow
