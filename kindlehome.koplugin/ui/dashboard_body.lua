local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Theme = require("lib/render/theme")

local DashboardBody = {}

local CARD_PAD = 10
local SECTION_GAP = 8

local FONT = {
    clock = 30,
    date = 14,
    status = 12,
    card_title = 11,
    temp = 24,
    body = 14,
    meta = 12,
    footer = 11,
}

local function px(config, dp)
    return Theme.native_size(config, dp)
end

local function face(config, dp)
    return Font:getFace("cfont", Theme.native_font_size(config, dp))
end

local function gap(config, dp)
    return VerticalSpan:new{ width = px(config, dp) }
end

local function text_box(text, width, config, dp, bold)
    return TextBoxWidget:new{
        text = tostring(text or ""),
        width = width,
        face = face(config, dp),
        bold = bold or nil,
    }
end

local function text_line(text, config, dp, bold)
    return TextWidget:new{
        text = tostring(text or ""),
        face = face(config, dp),
        bold = bold or nil,
    }
end

local function add_text(group, text, width, config, dp, bold)
    if text == nil or text == "" then return end
    table.insert(group, text_box(text, width, config, dp, bold))
    table.insert(group, gap(config, 3))
end

local function full_width(inner_w, widget)
    return LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = widget:getSize().h },
        widget,
    }
end

local function card(config, inner_w, content)
    local pad = px(config, CARD_PAD)
    local border = Size.border.window
    local content_w = math.max(1, inner_w - 2 * (border + pad))
    local sized = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = content:getSize().h },
        content,
    }
    return FrameContainer:new{
        margin = 0,
        padding = pad,
        bordersize = border,
        background = Blitbuffer.COLOR_WHITE,
        sized,
    }
end

local HnRow = InputContainer:extend{}

function HnRow:init()
    self[1] = self.content_group
    local size = self.content_group:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapHnRow = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function HnRow:onTapHnRow()
    if type(self.on_tap) ~= "function" then return false end
    self.on_tap()
    return true
end

local function build_hero(model, config, inner_w)
    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, text_line(model.hero.clock, config, FONT.clock, true))
    table.insert(group, gap(config, 2))
    table.insert(group, text_line(model.hero.date, config, FONT.date))
    return full_width(inner_w, group)
end

local function build_weather(model, config, inner_w)
    local weather = model.weather
    if not weather then return nil end
    local content = VerticalGroup:new{ align = "left" }
    local content_w = math.max(1, inner_w - 2 * (Size.border.window + px(config, CARD_PAD)))
    table.insert(content, text_line(weather.title, config, FONT.card_title, true))
    table.insert(content, gap(config, 5))
    add_text(content, weather.temp, content_w, config, FONT.temp, true)
    add_text(content, weather.condition, content_w, config, FONT.body)
    add_text(content, weather.fallback, content_w, config, FONT.body)
    add_text(content, weather.detail, content_w, config, FONT.meta)
    add_text(content, weather.updated, content_w, config, FONT.meta)
    add_text(content, weather.message, content_w, config, FONT.meta)
    return card(config, inner_w, content)
end

local function build_hn(model, config, inner_w, callbacks)
    local hn = model.hn
    if not hn then return nil end
    local content = VerticalGroup:new{ align = "left" }
    local content_w = math.max(1, inner_w - 2 * (Size.border.window + px(config, CARD_PAD)))
    table.insert(content, text_line(hn.title, config, FONT.card_title, true))
    table.insert(content, gap(config, 5))

    if #hn.items == 0 then
        add_text(content, hn.empty, content_w, config, FONT.body)
    else
        for index, row in ipairs(hn.items) do
            if index > 1 then
                table.insert(content, LineWidget:new{
                    dimen = Geom:new{ w = content_w, h = Size.line.thin },
                })
                table.insert(content, gap(config, 4))
            end
            local row_group = VerticalGroup:new{ align = "left" }
            add_text(row_group, row.rank .. ". " .. row.title, content_w, config, FONT.body, true)
            add_text(row_group, row.meta, content_w, config, FONT.meta)
            table.insert(content, HnRow:new{
                content_group = row_group,
                on_tap = row.id and function() callbacks.on_open_hn(row.id) end or nil,
            })
            table.insert(content, gap(config, 4))
        end
    end

    add_text(content, hn.message, content_w, config, FONT.meta)
    add_text(content, hn.updated, content_w, config, FONT.meta)
    return card(config, inner_w, content)
end

local function build_digest(model, config, inner_w)
    local digest = model.digest
    if not digest then return nil end
    local content = VerticalGroup:new{ align = "left" }
    local content_w = math.max(1, inner_w - 2 * (Size.border.window + px(config, CARD_PAD)))
    table.insert(content, text_line(digest.title, config, FONT.card_title, true))
    table.insert(content, gap(config, 5))
    if digest.available then
        add_text(content, "Available: " .. digest.date, content_w, config, FONT.body)
    else
        add_text(content, "Not generated yet.", content_w, config, FONT.body)
        add_text(content, "Use the Digest button below to create today's summary.", content_w, config, FONT.meta)
    end
    return card(config, inner_w, content)
end

local function build_test(model, config, inner_w, callbacks)
    if not model.test_article then return nil end
    local content = VerticalGroup:new{ align = "left" }
    local content_w = math.max(1, inner_w - 2 * (Size.border.window + px(config, CARD_PAD)))
    table.insert(content, text_line("DEVELOPMENT", config, FONT.card_title, true))
    table.insert(content, gap(config, 5))
    local row_group = VerticalGroup:new{ align = "left" }
    add_text(row_group, "Open test article", content_w, config, FONT.body)
    table.insert(content, HnRow:new{
        content_group = row_group,
        on_tap = function() callbacks.on_test() end,
    })
    return card(config, inner_w, content)
end

function DashboardBody.build(model, config, width, height, callbacks)
    callbacks = callbacks or {}
    local bar = ScrollableContainer:getScrollbarWidth()
    local inner_w = math.max(1, width - bar)
    local root = VerticalGroup:new{ align = "left" }

    local function add_section(widget)
        if not widget then return end
        table.insert(root, widget)
        table.insert(root, gap(config, SECTION_GAP))
    end

    add_section(build_hero(model, config, inner_w))
    if model.status then
        add_section(full_width(inner_w, text_box(model.status, inner_w, config, FONT.status)))
    end
    if model.hint then
        local content = VerticalGroup:new{ align = "left" }
        add_text(content, model.hint, math.max(1, inner_w - 2 * (Size.border.window + px(config, CARD_PAD))), config, FONT.status)
        add_section(card(config, inner_w, content))
    end
    add_section(build_weather(model, config, inner_w))
    add_section(build_hn(model, config, inner_w, callbacks))
    add_section(build_digest(model, config, inner_w))
    add_section(build_test(model, config, inner_w, callbacks))
    add_section(full_width(inner_w, text_box(model.footer, inner_w, config, FONT.footer)))

    local page = LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = root:getSize().h },
        root,
    }
    return ScrollableContainer:new{
        dimen = Geom:new{ w = width, h = height },
        page,
    }
end

return DashboardBody
