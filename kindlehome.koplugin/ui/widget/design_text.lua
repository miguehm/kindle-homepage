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

local function line_height(role)
    return Theme.line_height[role] or 0.3
end

function M.box(text, width, config, role, bold, fgcolor)
    return TextBoxWidget:new{
        text = tostring(text or ""),
        width = math.max(1, width),
        face = Theme.face(config, role, bold),
        bold = bold or nil,
        fgcolor = fgcolor or Theme.color.fg,
        line_height = line_height(role),
    }
end

-- Like box(), but never taller than `max_lines`: longer text is cut with an
-- ellipsis. Short text keeps its natural height, so a one-line title does not
-- reserve two lines. Costs a second build only when the text overflows.
function M.box_lines(text, width, config, role, bold, fgcolor, max_lines)
    local widget = M.box(text, width, config, role, bold, fgcolor)
    local face = widget.face
    max_lines = tonumber(max_lines) or 2
    local size = tonumber(face and face.size)
    if not size then return widget end
    local line_px = math.floor((1 + line_height(role)) * size)
    local limit = line_px * max_lines
    if widget:getSize().h <= limit then return widget end
    if type(widget.free) == "function" then widget:free() end
    return TextBoxWidget:new{
        text = tostring(text or ""),
        width = math.max(1, width),
        height = limit,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        face = face,
        bold = bold or nil,
        fgcolor = fgcolor or Theme.color.fg,
        line_height = line_height(role),
    }
end

-- Single line truncated with an ellipsis to `max_width`.
function M.line_fit(text, max_width, config, role, bold, fgcolor)
    return TextWidget:new{
        text = tostring(text or ""),
        face = Theme.face(config, role, bold),
        bold = bold or nil,
        fgcolor = fgcolor or Theme.color.fg,
        max_width = math.max(1, max_width),
        truncate_with_ellipsis = true,
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
