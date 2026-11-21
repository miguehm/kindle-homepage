-- Native dashboard body: a content column that fits the available height when
-- it can, with a native ScrollableContainer only as an extreme fallback
-- (large ui_font_scale or landscape). The bottom tab bar stays fixed outside
-- the content. The wrapper reports the content area as its crop region so
-- KOReader repaints the right framebuffer slice (F9/F15 invariant).
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local HeroWeather = require("ui/widget/hero_weather")
local StoriesCard = require("ui/widget/stories_card")
local BottomNav = require("ui/widget/bottom_nav")
local TapRow = require("ui/widget/tap_row")

local DashboardBody = {}

local SECTION_GAP = 8
local PAGE_SIZE_CHOICES = { 4, 3, 2, 1 }

local BodyWrapper = InputContainer:extend{}

function BodyWrapper:getCropRegion()
    if self.scroll and type(self.scroll.getCropRegion) == "function" then
        return self.scroll:getCropRegion()
    end
    return self.dimen
end

local function assemble(sections, config)
    local root = VerticalGroup:new{ align = "left" }
    for index, section in ipairs(sections) do
        if index > 1 then
            table.insert(root, DesignText.span(config, SECTION_GAP))
        end
        table.insert(root, section)
    end
    return root
end

local function build_sections(model, config, content_w, callbacks, fill_height)
    local sections = {}
    table.insert(sections, HeroWeather.build(
        model.hero, config, content_w, model.weather, callbacks.plugin_dir))

    if model.hint then
        table.insert(sections, DesignText.box(
            model.hint, content_w, config, "body_sm", false, Theme.color.muted))
    end
    local card = nil
    if model.hn then
        card = StoriesCard.build(
            model.hn, config, content_w, callbacks, callbacks.plugin_dir, fill_height)
        table.insert(sections, card)
    end
    if model.test_article then
        local dev = VerticalGroup:new{ align = "left" }
        table.insert(dev, DesignText.line("DEVELOPMENT", config, "label_md", true, Theme.color.muted))
        table.insert(dev, DesignText.span(config, 4))
        table.insert(dev, TapRow:new{
            content_group = DesignText.box("Open test article", content_w, config, "body_md"),
            show_parent = callbacks.show_parent,
            on_tap = callbacks.on_test,
        })
        table.insert(sections, FrameContainer:new{
            margin = 0,
            padding = Theme.native_size(config, 8),
            bordersize = Theme.hairline(config),
            color = Theme.color.hairline,
            background = Theme.color.canvas,
            dev,
        })
    end
    return sections, card
end

local function model_for_page(callbacks, model, page_size)
    if type(callbacks.model_for) == "function" then
        return callbacks.model_for(page_size) or model
    end
    return model
end

local function build_page(model_for_build, config, content_w, callbacks, fill_height)
    local sections, card = build_sections(model_for_build, config, content_w, callbacks, fill_height)
    local root = assemble(sections, config)
    local page = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = root:getSize().h },
        root,
    }
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, HorizontalSpan:new{ width = Theme.margin(config) })
    table.insert(row, page)
    return page, root, row, card
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
    local viewport_h = math.max(1, height - nav_height)
    local bar = ScrollableContainer:getScrollbarWidth()
    local margin = Theme.margin(config)
    local content_w = math.max(1, width - 2 * margin)

    local chosen_model, chosen_size, page, root, row, card
    for _, page_size in ipairs(PAGE_SIZE_CHOICES) do
        chosen_model = model_for_page(callbacks, model, page_size)
        page, root, row, card = build_page(chosen_model, config, content_w, callbacks)
        chosen_size = page_size
        if root:getSize().h <= viewport_h then
            break
        end
    end

    local scroll = nil
    local filler = nil
    local viewport
    if root:getSize().h > viewport_h then
        content_w = math.max(1, width - bar - 2 * margin)
        chosen_model = model_for_page(callbacks, model, PAGE_SIZE_CHOICES[#PAGE_SIZE_CHOICES])
        page, root, row, card = build_page(chosen_model, config, content_w, callbacks)
        chosen_size = PAGE_SIZE_CHOICES[#PAGE_SIZE_CHOICES]
        scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = viewport_h },
            row,
        }
        scroll.dialog = callbacks.show_parent
        scroll.show_parent = callbacks.show_parent
        viewport = scroll
    else
        if card then
            local extra = viewport_h - root:getSize().h
            if extra > 0 then
                StoriesCard.apply_fill(card, card:getSize().h + extra)
                if root.resetLayout then root:resetLayout() end
                page.dimen = Geom:new{ w = content_w, h = root:getSize().h }
                if row.resetLayout then row:resetLayout() end
            end
        end
        filler = VerticalSpan:new{ width = math.max(0, viewport_h - row:getSize().h) }
        viewport = row
    end

    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, viewport)
    if filler then
        table.insert(group, filler)
    end
    table.insert(group, nav)

    local body = BodyWrapper:new{}
    body[1] = group
    body.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    body.scroll = scroll
    body.viewport = viewport
    body.filler = filler
    body.nav = nav
    body.page = page
    body.model = chosen_model
    body.page_size = chosen_size
    body.content_width = content_w
    body.fits = scroll == nil
    return body
end

return DashboardBody
