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
local DEFAULT_PAGE_SIZE = 4
local MAX_PAGE_SIZE = 10

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

    local preferred = DEFAULT_PAGE_SIZE
    if config and type(config.get) == "function" then
        preferred = tonumber(config:get("hn_items_per_page")) or DEFAULT_PAGE_SIZE
    end
    preferred = math.floor(preferred)
    if preferred < 1 then preferred = 1 end
    if preferred > MAX_PAGE_SIZE then preferred = MAX_PAGE_SIZE end

    local probes = 0
    local function measure(page_size)
        probes = probes + 1
        local measured_model = model_for_page(callbacks, model, page_size)
        local measured_page, measured_root, measured_row, measured_card =
            build_page(measured_model, config, content_w, callbacks)
        return {
            size = page_size,
            model = measured_model,
            page = measured_page,
            root = measured_root,
            row = measured_row,
            card = measured_card,
            fits = measured_root:getSize().h <= viewport_h,
        }
    end

    -- Fast path: the preferred size is the common case and costs one build.
    -- If it overflows, the page height is monotonic in the row count, so a
    -- binary search finds the largest size that still fits (bounded to
    -- 1 + ceil(log2(preferred)) builds instead of preferred builds).
    local chosen = measure(preferred)
    if not chosen.fits then
        local best_fit = nil
        local lo, hi = 1, preferred - 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local probe = measure(mid)
            if probe.fits then
                best_fit = probe
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        chosen = best_fit
    end

    local chosen_model, chosen_size, page, root, row, card
    local scroll = nil
    local filler = nil
    local viewport
    if not chosen then
        content_w = math.max(1, width - bar - 2 * margin)
        chosen = measure(1)
        chosen_model = chosen.model
        chosen_size = chosen.size
        page, root, row, card = chosen.page, chosen.root, chosen.row, chosen.card
        scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = viewport_h },
            row,
        }
        scroll.dialog = callbacks.show_parent
        scroll.show_parent = callbacks.show_parent
        viewport = scroll
    else
        chosen_model = chosen.model
        chosen_size = chosen.size
        page, root, row, card = chosen.page, chosen.root, chosen.row, chosen.card
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
    body.page_size_preferred = preferred
    body.probes = probes
    body.content_width = content_w
    body.fits = scroll == nil
    return body
end

return DashboardBody
