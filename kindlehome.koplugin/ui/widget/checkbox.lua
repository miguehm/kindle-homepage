-- SPDX-License-Identifier: MIT
-- DESIGN.md checkbox: a sharp 16dp square with a 1px black outline and a
-- solid 10dp inner square when checked, centered in a 48dp touch slot.
-- Drawn with paintRect only (no glyphs, no arcs, no grays).
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local Theme = require("lib/render/theme")
local PressFeedback = require("ui/widget/press_feedback")

local Checkbox = InputContainer:extend{
    checked = false,
    config = nil,
    on_tap = nil,
    show_parent = nil,
}

function Checkbox:init()
    self.show_parent = self.show_parent or self
    local hit = Theme.hit_size(self.config)
    self.box = Theme.px(self.config, "check")
    self.fill = Theme.px(self.config, "check_fill")
    self.thickness = Theme.hairline(self.config)
    self.dimen = Geom:new{ x = 0, y = 0, w = hit, h = hit }
    self.ges_events = {
        TapCheckbox = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function Checkbox:getSize()
    return self.dimen
end

function Checkbox:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local box, t = self.box, self.thickness
    local bx = x + math.floor((self.dimen.w - box) / 2)
    local by = y + math.floor((self.dimen.h - box) / 2)
    local color = Theme.color.fg
    bb:paintRect(bx, by, box, t, color)
    bb:paintRect(bx, by + box - t, box, t, color)
    bb:paintRect(bx, by, t, box, color)
    bb:paintRect(bx + box - t, by, t, box, color)
    if self.checked then
        local inset = math.floor((box - self.fill) / 2)
        bb:paintRect(bx + inset, by + inset, self.fill, self.fill, color)
    end
    PressFeedback.paint(self, bb, x, y)
end

function Checkbox:onTapCheckbox()
    return PressFeedback.run(self, self.on_tap)
end

return Checkbox
