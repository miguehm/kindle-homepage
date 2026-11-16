-- Native action bar: icon + short label per button.
--
-- Links inside HTML bodies are tiny, scroll away with the content,
-- and provide no pressed state. The primary actions therefore live here, in a
-- fixed footer that always stays reachable. Buttons use MDLight icons (no
-- unicode glyphs: MuPDF's HTML font substitution is unreliable on e-ink).

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")

local Screen = Device.screen

local ActionButton = InputContainer:extend{
    icon = nil,
    label = nil,
    callback = nil,
    config = nil,
    width = nil,
    height = nil,
    enabled = true,
    show_parent = nil,
}

function ActionButton:init()
    self.show_parent = self.show_parent or self
    self.height = self.height or Theme.native_size(self.config, 58)
    self.width = self.width or Screen:getWidth()

    local padding = Theme.native_size(self.config, 6)
    local icon_size = Theme.native_size(self.config, 24)
    local face = Font:getFace("cfont", Theme.native_font_size(self.config, 12))

    local group = VerticalGroup:new{ align = "center" }
    table.insert(group, IconWidget:new{
        icon = self.icon,
        width = icon_size,
        height = icon_size,
        dim = not self.enabled,
    })
    table.insert(group, VerticalSpan:new{ width = Theme.native_size(self.config, 3) })
    table.insert(group, TextWidget:new{
        text = self.label or "",
        face = face,
        bold = true,
        max_width = self.width - 2 * padding,
    })

    self.frame = FrameContainer:new{
        margin = 0,
        bordersize = Size.border.button,
        background = Blitbuffer.COLOR_WHITE,
        padding = padding,
        show_parent = self.show_parent,
        group,
    }

    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        self.frame,
    }
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.ges_events = {
        TapActionButton = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function ActionButton:onTapActionButton()
    if self.enabled == false then return true end
    UIManager:setDirty(self.show_parent, "ui")
    if type(self.callback) == "function" then self.callback() end
    return true
end

local ActionBar = InputContainer:extend{
    buttons = nil,
    config = nil,
    show_parent = nil,
    background = nil,
}

function ActionBar:init()
    self.show_parent = self.show_parent or self
    local specs = self.buttons or {}
    local count = #specs

    local outer = Theme.native_size(self.config, 8)
    local gap = Theme.native_size(self.config, 6)
    local width = math.floor((Screen:getWidth() - 2 * outer - gap * (count - 1)) / math.max(count, 1))

    local row = HorizontalGroup:new{ align = "center" }
    for index, spec in ipairs(specs) do
        table.insert(row, ActionButton:new{
            icon = spec.icon,
            label = spec.label,
            callback = spec.callback,
            enabled = spec.enabled ~= false,
            config = self.config,
            width = width,
            show_parent = self.show_parent,
        })
        if index < count then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
    end

    self[1] = FrameContainer:new{
        margin = 0,
        padding = outer,
        bordersize = 0,
        background = self.background or Blitbuffer.COLOR_WHITE,
        row,
    }
    self.dimen = self[1]:getSize()
end

return ActionBar
