-- SPDX-License-Identifier: MIT
-- Sharp rectangular battery indicator: 1px outline, solid fill by capacity.
-- Drawn with paintRect only, so no arcs/grays are introduced on e-ink.
--
-- It MUST be a real Widget: KOReader propagates touch events to every child of
-- a container, and plain tables have no handleEvent() (crash on first tap).
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local Theme = require("lib/render/theme")

local BatteryGlyph = Widget:extend{
    config = nil,
    capacity = 0,
    charging = false,
}

function BatteryGlyph:init()
    local config = self.config
    self.capacity = tonumber(self.capacity) or 0
    if self.capacity < 0 then self.capacity = 0 end
    if self.capacity > 100 then self.capacity = 100 end
    self.width = Theme.native_size(config, 30)
    self.height = Theme.native_size(config, 14)
    self.thickness = Theme.hairline(config)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width + self.thickness * 2, h = self.height }
end

function BatteryGlyph:getSize()
    return self.dimen
end

function BatteryGlyph:paintTo(bb, x, y)
    local t = self.thickness
    local w, h = self.width, self.height
    local color = Theme.color.fg
    bb:paintRect(x, y, w, t, color)
    bb:paintRect(x, y + h - t, w, t, color)
    bb:paintRect(x, y, t, h, color)
    bb:paintRect(x + w - t, y, t, h, color)
    bb:paintRect(x + w, y + math.floor(h / 3), t, math.max(1, math.floor(h / 3)), color)
    local inner_w = w - 2 * t
    local fill = math.floor(inner_w * self.capacity / 100)
    if self.charging or fill > 0 then
        if fill > inner_w then fill = inner_w end
        bb:paintRect(x + t, y + t, fill, h - 2 * t, color)
    end
end

return BatteryGlyph
