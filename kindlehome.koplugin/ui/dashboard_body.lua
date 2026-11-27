-- SPDX-License-Identifier: MIT
-- Native dashboard body: a content column that fits the available height when
-- it can, with a native ScrollableContainer only as an extreme fallback
-- (large ui_font_scale or landscape). The bottom tab bar stays fixed outside
-- the content. The BodyWrapper reports the content area through
-- getCropRegion() so KOReader repaints the right framebuffer slice.
--
-- Cost model (Kindle CPU):
-- - The hero, hint and nav are built once per body. Fitting the story rows
--   only rebuilds the stories card, never the whole page.
-- - Rows are measured on the longest titles of the feed (worst case), so the
--   chosen row count fits every page and paging never changes the layout.
-- - The chosen count is cached by layout key; a rebuild with the same key
--   skips measuring entirely. Page turns swap only the stories card.
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local BodyWrapper = require("ui/widget/body_wrapper")
local NoticeBox = require("ui/widget/notice_box")
local HeroWeather = require("ui/widget/hero_weather")
local StoriesCard = require("ui/widget/stories_card")
local BottomNav = require("ui/widget/bottom_nav")

local DashboardBody = {}

local DEFAULT_PAGE_SIZE = 4
local MAX_PAGE_SIZE = 10

local function free(widget)
    if widget and type(widget.free) == "function" then widget:free() end
end

local function preferred_size(config)
    local preferred = DEFAULT_PAGE_SIZE
    if config and type(config.get) == "function" then
        preferred = tonumber(config:get("hn_items_per_page")) or DEFAULT_PAGE_SIZE
    end
    preferred = math.floor(preferred)
    if preferred < 1 then preferred = 1 end
    if preferred > MAX_PAGE_SIZE then preferred = MAX_PAGE_SIZE end
    return preferred
end

local function model_for_page(callbacks, model, page_size, worst_case)
    if type(callbacks.model_for) == "function" then
        return callbacks.model_for(page_size, worst_case) or model
    end
    return model
end

function DashboardBody.build_hero(model, config, content_w, callbacks)
    return HeroWeather.build(model.hero, config, content_w, model.weather, callbacks.plugin_dir)
end

-- The stories card alone; `fill_height` stretches it with the pager anchored
-- to the bottom edge.
function DashboardBody.build_card(model, config, content_w, callbacks, fill_height)
    if not model.hn then return nil end
    local card = StoriesCard.build(model.hn, config, content_w, callbacks, callbacks.plugin_dir)
    if fill_height then StoriesCard.apply_fill(card, fill_height) end
    return card
end

-- Sections that do not depend on the row count, built once per body.
local function build_fixed(model, config, content_w, callbacks)
    local fixed = {}
    table.insert(fixed, { key = "hero", widget = DashboardBody.build_hero(model, config, content_w, callbacks) })
    if model.hint then
        table.insert(fixed, { key = "hint", widget = NoticeBox.build(model.hint, content_w, config, {
            on_retry = callbacks.on_refresh, show_parent = callbacks.show_parent,
        }) })
    end
    return fixed
end

local function assemble(fixed, card, config)
    local root = VerticalGroup:new{ align = "left" }
    local gap = Theme.px(config, "section_gap")
    for _, section in ipairs(fixed) do
        if #root > 0 then table.insert(root, VerticalSpan:new{ width = gap }) end
        table.insert(root, section.widget)
    end
    if card then
        if #root > 0 then table.insert(root, VerticalSpan:new{ width = gap }) end
        table.insert(root, card)
    end
    return root
end

local function fixed_height(fixed)
    local h = 0
    for _, section in ipairs(fixed) do h = h + section.widget:getSize().h end
    return h
end

-- Everything that can change which row count fits. Equal keys reuse the
-- cached count without measuring.
local function layout_key(model, config, viewport_h, content_w, preferred, fixed)
    local hn = model.hn or {}
    return table.concat({
        viewport_h, content_w, preferred, Theme.scale(config), fixed_height(fixed), #fixed,
        hn.total or 0, hn.longest_title or 0, hn.message and 1 or 0,
    }, ":")
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
    local preferred = preferred_size(config)
    local fixed = build_fixed(model, config, content_w, callbacks)
    local key = layout_key(model, config, viewport_h, content_w, preferred, fixed)

    local probes = 0
    local function measure(page_size)
        probes = probes + 1
        local measured_model = model_for_page(callbacks, model, page_size, true)
        local measured_card = DashboardBody.build_card(measured_model, config, content_w, callbacks)
        local measured_root = assemble(fixed, measured_card, config)
        local result = {
            size = page_size,
            fits = measured_root:getSize().h <= viewport_h,
        }
        free(measured_card)
        return result
    end

    -- Fast paths: a cached count for this layout costs no probe; otherwise
    -- the preferred size is the common case and costs one card build. If it
    -- overflows, the card height is monotonic in the row count, so a binary
    -- search finds the largest size that still fits (bounded to
    -- 1 + ceil(log2(preferred)) card builds).
    local cached = callbacks.layout
    local chosen
    if cached and cached.key == key and cached.size then
        chosen = { size = cached.size, fits = true }
    elseif not model.hn then
        chosen = { size = preferred, fits = assemble(fixed, nil, config):getSize().h <= viewport_h }
        if not chosen.fits then chosen = nil end
    else
        chosen = measure(preferred)
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
    end

    local chosen_model, chosen_size, page, root, row, card
    local scroll = nil
    local filler = nil
    local viewport
    if not chosen then
        content_w = math.max(1, width - bar - 2 * margin)
        chosen_size = 1
        chosen_model = model_for_page(callbacks, model, chosen_size)
        for _, section in ipairs(fixed) do free(section.widget) end
        fixed = build_fixed(chosen_model, config, content_w, callbacks)
        card = DashboardBody.build_card(chosen_model, config, content_w, callbacks)
        root = assemble(fixed, card, config)
        page = LeftContainer:new{ dimen = Geom:new{ w = content_w, h = root:getSize().h }, root }
        row = HorizontalGroup:new{ align = "top" }
        table.insert(row, HorizontalSpan:new{ width = Theme.margin(config) })
        table.insert(row, page)
        scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = viewport_h },
            row,
        }
        scroll.dialog = callbacks.show_parent
        scroll.show_parent = callbacks.show_parent
        viewport = scroll
    else
        chosen_size = chosen.size
        chosen_model = model_for_page(callbacks, model, chosen_size)
        card = DashboardBody.build_card(chosen_model, config, content_w, callbacks)
        root = assemble(fixed, card, config)
        if card then
            local extra = viewport_h - root:getSize().h
            if extra > 0 then
                StoriesCard.apply_fill(card, card:getSize().h + extra)
                if root.resetLayout then root:resetLayout() end
            end
        end
        page = LeftContainer:new{ dimen = Geom:new{ w = content_w, h = root:getSize().h }, root }
        row = HorizontalGroup:new{ align = "top" }
        table.insert(row, HorizontalSpan:new{ width = Theme.margin(config) })
        table.insert(row, page)
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
    body.root = root
    body.card = card
    body.model = chosen_model
    body.page_size = chosen_size
    body.page_size_preferred = preferred
    body.probes = probes
    body.content_width = content_w
    body.fits = scroll == nil
    body.layout = body.fits and { key = key, size = chosen_size } or nil

    -- Section offsets inside the body, for in-place swaps.
    local y = 0
    for index, child in ipairs(root) do
        for _, section in ipairs(fixed) do
            if child == section.widget then body:track_section(section.key, root, index, margin, y) end
        end
        if child == card then body:track_section("stories", root, index, margin, y) end
        y = y + child:getSize().h
    end
    if body.fits and chosen_model.hn and (chosen_model.hn.pages or 0) > 1 then
        body:enable_swipe(callbacks.on_next_page, callbacks.on_prev_page)
    end
    return body
end

return DashboardBody
