-- SPDX-License-Identifier: MIT
-- Dashboard header: literary title on the left, settings and close on the
-- right, separated from the body by a single hairline. It replaces TitleBar
-- only for the dashboard; the article shell keeps the native TitleBar.
--
-- This MUST be a real InputContainer (not a plain table): Shell calls
-- getSize() for layout and UIManager calls paintTo() for every child.
local Device = require("device")
local Geom = require("ui/geometry")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local TapIcon = require("ui/widget/tap_icon")

local Screen = Device.screen

local DashboardHeader = InputContainer:extend{
    title = "Kindle Home",
    config = nil,
    on_settings = nil,
    on_close = nil,
    show_parent = nil,
    plugin_dir = nil,
    settings_button = nil,
    close_button = nil,
}

function DashboardHeader:init()
    local config = self.config
    local width = Screen:getWidth()
    local margin = Theme.margin(config)
    local hairline = Theme.hairline(config)
    local icon_size = Theme.px(config, "icon")
    local slot = Theme.hit_size(config)
    local icon_gap = Theme.native_size(config, Theme.space.xs)
    local height = math.max(Theme.px(config, "header_h"), slot)
    local title_gap = Theme.native_size(config, Theme.space.sm)

    local title_limit = math.max(1, width - 2 * margin - 2 * slot - icon_gap)
    local title = TextWidget:new{
        text = self.title or "Kindle Home",
        face = Theme.face(config, "headline_md", true),
        bold = true,
        fgcolor = Theme.color.fg,
        max_width = title_limit,
        truncate_with_ellipsis = true,
    }

    local settings_file = Theme.icon_file(self.plugin_dir, "header", "settings", false)
    local close_file = Theme.icon_file(self.plugin_dir, "header", "close", false)

    self.settings_button = TapIcon:new{
        icon = (not settings_file) and "appbar.settings" or nil,
        file = settings_file,
        width = icon_size,
        height = icon_size,
        config = config,
        show_parent = self.show_parent or self,
        on_tap = self.on_settings,
    }
    self.close_button = TapIcon:new{
        icon = (not close_file) and "close" or nil,
        file = close_file,
        width = icon_size,
        height = icon_size,
        config = config,
        show_parent = self.show_parent or self,
        on_tap = self.on_close,
    }
    local filler = math.max(0, width - 2 * margin - title:getSize().w
        - self.settings_button:getSize().w - self.close_button:getSize().w - icon_gap)

    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, HorizontalSpan:new{ width = margin })
    table.insert(row, title)
    table.insert(row, HorizontalSpan:new{ width = filler })
    table.insert(row, self.settings_button)
    table.insert(row, HorizontalSpan:new{ width = icon_gap })
    table.insert(row, self.close_button)
    table.insert(row, HorizontalSpan:new{ width = margin })

    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        row,
    })
    table.insert(group, VerticalSpan:new{ width = title_gap })
    table.insert(group, LineWidget:new{
        dimen = Geom:new{ w = width, h = hairline },
        background = Theme.color.hairline,
    })

    self[1] = group
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height + title_gap + hairline }
end

return DashboardHeader
