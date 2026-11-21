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
    local icon_size = Theme.native_size(config, 28)
    local icon_gap = Theme.native_size(config, Theme.space.md)
    local height = Theme.native_size(config, 52)
    local title_gap = Theme.native_size(config, Theme.space.sm)

    local title_limit = math.max(1, width - 2 * margin - 2 * icon_size - icon_gap)
    local title = TextWidget:new{
        text = self.title or "Kindle Home",
        face = Theme.face(config, "headline_md", true),
        bold = true,
        fgcolor = Theme.color.fg,
        max_width = title_limit,
        truncate_with_ellipsis = true,
    }
    local filler = math.max(0, width - 2 * margin - title:getSize().w - 2 * icon_size - icon_gap)

    local settings_file = Theme.icon_file(self.plugin_dir, "header", "settings", false)
    local close_file = Theme.icon_file(self.plugin_dir, "header", "close", false)

    self.settings_button = TapIcon:new{
        icon = settings_file and nil or "appbar.settings",
        file = settings_file,
        width = icon_size,
        height = icon_size,
        show_parent = self.show_parent or self,
        on_tap = self.on_settings,
    }
    self.close_button = TapIcon:new{
        icon = close_file and nil or "close",
        file = close_file,
        width = icon_size,
        height = icon_size,
        show_parent = self.show_parent or self,
        on_tap = self.on_close,
    }

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
