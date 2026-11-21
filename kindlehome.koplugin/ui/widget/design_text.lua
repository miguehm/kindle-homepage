-- SPDX-License-Identifier: MIT
-- Shared native text/layout helpers for the dashboard widgets.
local Geom = require("ui/geometry")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")

local M = {}

function M.line(text, config, role, bold, fgcolor)
    return TextWidget:new{
        text = tostring(text or ""),
        face = Theme.face(config, role, bold),
        bold = bold or nil,
        fgcolor = fgcolor or Theme.color.fg,
    }
end

function M.box(text, width, config, role, bold, fgcolor)
    return TextBoxWidget:new{
        text = tostring(text or ""),
        width = math.max(1, width),
        face = Theme.face(config, role, bold),
        bold = bold or nil,
        fgcolor = fgcolor or Theme.color.fg,
    }
end

function M.span(config, dp)
    return VerticalSpan:new{ width = Theme.native_size(config, dp) }
end

function M.divider(config, width, color)
    return LineWidget:new{
        dimen = Geom:new{ w = math.max(1, width), h = Theme.hairline(config) },
        background = color or Theme.color.hairline,
    }
end

return M
