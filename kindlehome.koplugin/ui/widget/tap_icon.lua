-- SPDX-License-Identifier: MIT
-- Sharp, monochrome icon tap target shared by the dashboard header, the
-- bottom navigation and the in-card actions. No ripples, no rounded corners.
--
-- The glyph is drawn at its visual size but centered in a slot of at least
-- Theme.hit_size() (48dp) on both axes, so the whole slot is tappable. An
-- optional `background` fills the slot (inverted pager buttons), which keeps
-- the drawn button and the touch target identical.
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")

local Theme = require("lib/render/theme")
local PressFeedback = require("ui/widget/press_feedback")

local TapIcon = InputContainer:extend{
    icon = nil,
    file = nil,
    width = nil,
    height = nil,
    alpha = false,
    dim = nil,
    config = nil,
    hit_size = nil,   -- px; defaults to Theme.hit_size(config)
    background = nil, -- optional slot fill
    on_tap = nil,
    show_parent = nil,
}

function TapIcon:init()
    self.show_parent = self.show_parent or self
    self.glyph = IconWidget:new{
        icon = self.icon,
        file = self.file,
        width = self.width,
        height = self.height,
        alpha = self.alpha,
        dim = self.dim,
    }
    local size = self.glyph:getSize()
    local hit = self.hit_size or Theme.hit_size(self.config)
    local w = math.max(size.w, hit)
    local h = math.max(size.h, hit)
    local slot = CenterContainer:new{
        dimen = Geom:new{ w = w, h = h },
        self.glyph,
    }
    -- Truthiness, not `~= nil`: under LuaJIT a color is FFI cdata and
    -- comparing it with nil runs its __eq metamethod, which errors.
    if self.background then
        slot = FrameContainer:new{
            margin = 0,
            padding = 0,
            bordersize = 0,
            background = self.background,
            slot,
        }
    end
    self[1] = slot
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.ges_events = {
        TapIcon = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function TapIcon:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
    PressFeedback.paint(self, bb, x, y)
end

function TapIcon:onTapIcon()
    return PressFeedback.run(self, self.on_tap)
end

return TapIcon
