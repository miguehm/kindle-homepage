-- Native dashboard body: a scrollable content column with a fixed bottom tab
-- bar. The wrapper reports the scroll area as its crop region so KOReader
-- repaints the right framebuffer slice (F9/F15 invariant).
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local HeroWeather = require("ui/widget/hero_weather")
local StoriesCard = require("ui/widget/stories_card")
local BottomNav = require("ui/widget/bottom_nav")
local TapRow = require("ui/widget/tap_row")

local DashboardBody = {}

local SECTION_GAP = 12

local BodyWrapper = InputContainer:extend{}

function BodyWrapper:getCropRegion()
    if self.scroll and type(self.scroll.getCropRegion) == "function" then
        return self.scroll:getCropRegion()
    end
    return self.dimen
end

local function add_section(root, widget, config)
    if not widget then return end
    table.insert(root, widget)
    table.insert(root, DesignText.span(config, SECTION_GAP))
end

function DashboardBody.build(model, config, width, height, callbacks)
    callbacks = callbacks or {}
    local nav = BottomNav:new{
        tabs = model.nav and model.nav.tabs,
        active = model.nav and model.nav.active,
        config = config,
        plugin_dir = callbacks.plugin_dir,
        on_tab = callbacks.on_nav,
        show_parent = callbacks.show_parent,
    }
    local nav_height = nav:getSize().h
    local scroll_height = math.max(1, height - nav_height)
    local bar = ScrollableContainer:getScrollbarWidth()
    local inner_w = math.max(1, width - bar)
    local margin = Theme.margin(config)
    local content_w = math.max(1, inner_w - 2 * margin)

    local root = VerticalGroup:new{ align = "left" }
    add_section(root, HeroWeather.build(model.hero, config, content_w, model.weather, callbacks.plugin_dir), config)

    if model.hint then
        add_section(root, DesignText.box(model.hint, content_w, config, "body_sm", false, Theme.color.muted), config)
    end
    if model.hn then
        add_section(root, StoriesCard.build(model.hn, config, content_w, callbacks, callbacks.plugin_dir), config)
    end
    if model.test_article then
        local dev = VerticalGroup:new{ align = "left" }
        table.insert(dev, DesignText.line("DEVELOPMENT", config, "label_md", true, Theme.color.muted))
        table.insert(dev, DesignText.span(config, 4))
        local row = TapRow:new{
            content_group = DesignText.box("Open test article", content_w, config, "body_md"),
            show_parent = callbacks.show_parent,
            on_tap = callbacks.on_test,
        }
        table.insert(dev, row)
        add_section(root, FrameContainer:new{
            margin = 0,
            padding = Theme.native_size(config, 8),
            bordersize = Theme.hairline(config),
            color = Theme.color.hairline,
            background = Theme.color.canvas,
            dev,
        }, config)
    end
    if model.last_refreshed then
        local label = DesignText.line(model.last_refreshed.text, config, "label_md", false, Theme.color.muted)
        local row = HorizontalGroup:new{ align = "center" }
        table.insert(row, HorizontalSpan:new{ width = math.max(0, content_w - label:getSize().w) })
        table.insert(row, label)
        add_section(root, LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = row:getSize().h }, row,
        }, config)
    end

    local page = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = root:getSize().h },
        root,
    }
    local scroll = ScrollableContainer:new{
        dimen = Geom:new{ w = width, h = scroll_height },
        page,
    }
    scroll.dialog = callbacks.show_parent
    scroll.show_parent = callbacks.show_parent

    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, scroll)
    table.insert(group, nav)

    local body = BodyWrapper:new{}
    body[1] = group
    body.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    body.scroll = scroll
    body.nav = nav
    return body
end

return DashboardBody
