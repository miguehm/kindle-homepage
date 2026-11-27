-- SPDX-License-Identifier: MIT
-- One style for every error/offline/stale notice inside a card: a 1px black
-- frame (DESIGN.md floating-chrome tier) with short body text and an optional
-- "Retry" action. Replaces muted text appended at the end of the cards.
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Geom = require("ui/geometry")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local TapRow = require("ui/widget/tap_row")

local NoticeBox = {}

local function retry_button(config, on_retry, show_parent)
    local border = Theme.hairline(config)
    local label = DesignText.line("Retry", config, "label_md", true)
    local pad = Theme.native_size(config, Theme.space.sm)
    local frame = FrameContainer:new{
        margin = 0,
        padding = pad,
        bordersize = border,
        color = Theme.color.fg,
        background = Theme.color.canvas,
        label,
    }
    return TapRow:new{
        content_group = frame,
        show_parent = show_parent,
        on_tap = on_retry,
    }
end

-- opts: { on_retry = fn, show_parent = shell }
function NoticeBox.build(text, width, config, opts)
    opts = opts or {}
    local border = Theme.hairline(config)
    local pad = Theme.native_size(config, Theme.space.sm)
    local inner_w = math.max(1, width - 2 * (border + pad))
    local button = nil
    local gap = Theme.native_size(config, Theme.space.sm)
    if type(opts.on_retry) == "function" then
        button = retry_button(config, opts.on_retry, opts.show_parent)
    end
    local text_w = inner_w - (button and (button:getSize().w + gap) or 0)
    local body = DesignText.box(text, math.max(1, text_w), config, "body_sm")
    local content
    if button then
        content = HorizontalGroup:new{ align = "center" }
        table.insert(content, LeftContainer:new{
            dimen = Geom:new{ w = math.max(1, text_w), h = body:getSize().h }, body,
        })
        table.insert(content, HorizontalSpan:new{ width = gap })
        table.insert(content, button)
    else
        content = body
    end
    local frame = FrameContainer:new{
        margin = 0,
        padding = pad,
        bordersize = border,
        color = Theme.color.fg,
        background = Theme.color.canvas,
        content,
    }
    frame.retry_button = button
    return frame
end

return NoticeBox
