-- SPDX-License-Identifier: MIT
-- Shared card pager: "Page N of M" on the left, prev/next on the right.
-- Each button is an inverted 48dp slot whose whole surface is tappable, and
-- the same component is used by Top Stories and TODO'S so both cards page
-- with identical controls in identical positions.
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local TapIcon = require("ui/widget/tap_icon")

local Pager = {}

local function button(name, fallback_icon, config, plugin_dir, on_tap, show_parent)
    local glyph = Theme.px(config, "icon")
    return TapIcon:new{
        icon = fallback_icon,
        file = Theme.icon_file(plugin_dir, "action", name, true),
        width = glyph,
        height = glyph,
        alpha = true,
        config = config,
        background = Theme.color.inverse_bg,
        show_parent = show_parent,
        on_tap = on_tap,
    }
end

function Pager.build(page, pages, config, content_w, callbacks, plugin_dir)
    local label = "Page " .. tostring(page) .. " of " .. tostring(pages)
    local label_widget = DesignText.line(label, config, "label_md", false, Theme.color.muted)
    local gap = Theme.native_size(config, Theme.space.sm)
    local prev = button("prev", "chevron.left", config, plugin_dir,
        callbacks.on_prev_page, callbacks.show_parent)
    local next_button = button("next", "chevron.right", config, plugin_dir,
        callbacks.on_next_page, callbacks.show_parent)
    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, label_widget)
    table.insert(row, HorizontalSpan:new{
        width = math.max(0, content_w - label_widget:getSize().w
            - prev:getSize().w - next_button:getSize().w - gap),
    })
    table.insert(row, prev)
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, next_button)
    row.prev_button = prev
    row.next_button = next_button
    return row
end

return Pager
