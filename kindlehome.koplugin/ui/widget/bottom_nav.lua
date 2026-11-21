-- SPDX-License-Identifier: MIT
-- Fixed three-tab bottom navigation. TODO'S and STORE are visual placeholders:
-- they report "Coming soon" and never change the active tab.
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")

local Screen = Device.screen

local LABELS = {
    dashboard = "DASHBOARD",
    todos = "TODO'S",
    store = "STORE",
}
local FALLBACK_ICONS = {
    dashboard = "home",
    todos = "notice-info",
    store = "appbar.filebrowser",
}

local NavCell = InputContainer:extend{
    name = nil,
    label = nil,
    active = false,
    width = nil,
    height = nil,
    on_tap = nil,
    show_parent = nil,
}

function NavCell:init()
    self.show_parent = self.show_parent or self
    local config = self.config
    local icon_size = Theme.native_size(config, 24)
    local icon = IconWidget:new{
        icon = FALLBACK_ICONS[self.name],
        file = Theme.icon_file(self.plugin_dir, "nav", self.name, self.active),
        width = icon_size,
        height = icon_size,
        alpha = self.active and true or false,
        dim = false,
    }
    local label = TextWidget:new{
        text = self.label or "",
        face = Theme.face(config, "label_lg", true),
        bold = true,
        fgcolor = self.active and Theme.color.inverse_fg or Theme.color.fg,
    }
    local group = VerticalGroup:new{ align = "center" }
    table.insert(group, icon)
    table.insert(group, VerticalSpan:new{ width = Theme.native_size(config, 4) })
    table.insert(group, label)

    local frame = FrameContainer:new{
        margin = 0,
        padding = 0,
        bordersize = 0,
        width = self.width,
        height = self.height,
        background = self.active and Theme.color.inverse_bg or Blitbuffer.COLOR_WHITE,
        show_parent = self.show_parent,
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            group,
        },
    }
    frame.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = frame
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapNavCell = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function NavCell:onTapNavCell()
    UIManager:setDirty(self.show_parent, "ui")
    if type(self.on_tap) == "function" then self.on_tap(self.name) end
    return true
end

local BottomNav = InputContainer:extend{
    tabs = nil,
    active = "dashboard",
    config = nil,
    plugin_dir = nil,
    on_tab = nil,
    show_parent = nil,
}

function BottomNav:init()
    self.show_parent = self.show_parent or self
    local config = self.config
    local tabs = self.tabs or { "dashboard", "todos", "store" }
    local width = Screen:getWidth()
    local hairline = Theme.hairline(config)
    local height = Theme.native_size(config, 52)
    local cell_width = math.floor(width / math.max(#tabs, 1))

    local row = HorizontalGroup:new{ align = "center" }
    for _, name in ipairs(tabs) do
        table.insert(row, NavCell:new{
            name = name,
            label = LABELS[name] or name:upper(),
            active = name == self.active,
            width = cell_width,
            height = height,
            config = config,
            plugin_dir = self.plugin_dir,
            show_parent = self.show_parent,
            on_tap = self.on_tab,
        })
    end

    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, LineWidget:new{
        dimen = Geom:new{ w = width, h = hairline },
        background = Theme.color.hairline,
    })
    table.insert(group, row)

    self[1] = group
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height + hairline }
end

return BottomNav
