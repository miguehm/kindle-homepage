-- SPDX-License-Identifier: MIT
-- TODO'S body: optional hint, filter chips (status + tags) and the TASKS card,
-- with the bottom nav fixed below. Same cost model as the dashboard body:
-- chips are built once per body, only the card is rebuilt while fitting rows,
-- rows are measured on the longest tasks across every filter, the chosen row
-- count is cached by layout key, and page turns or filter changes swap only
-- the sections that changed.
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local BodyWrapper = require("ui/widget/body_wrapper")
local DesignText = require("ui/widget/design_text")
local NoticeBox = require("ui/widget/notice_box")
local BottomNav = require("ui/widget/bottom_nav")
local TagChips = require("ui/widget/tag_chips")
local TodosCard = require("ui/widget/todos_card")

local TodosBody = {}

local DEFAULT_ROWS = 6
local MAX_ROWS = 10

local function free(widget)
    if widget and type(widget.free) == "function" then widget:free() end
end

-- Status chips and tag chips stacked as one "filters" section.
function TodosBody.build_filters(model, config, content_w, callbacks)
    if not model.todos then return nil end
    local group = VerticalGroup:new{ align = "left" }
    local status_chips = TagChips.build_status(model.todos, config, content_w, {
        on_status = callbacks.on_status,
        show_parent = callbacks.show_parent,
    })
    if status_chips then table.insert(group, status_chips) end
    local chips = TagChips.build(model.todos, config, content_w, {
        on_tag = callbacks.on_tag,
        on_tag_doc = callbacks.on_tag_doc,
        show_parent = callbacks.show_parent,
    })
    if chips then
        if #group > 0 then table.insert(group, DesignText.span(config, Theme.space.sm)) end
        table.insert(group, chips)
    end
    if #group == 0 then return nil end
    return group
end

function TodosBody.build_card(model, config, content_w, callbacks, fill_height)
    if not model.todos then return nil end
    return TodosCard.build(model.todos, config, content_w, callbacks, fill_height)
end

local function build_fixed(model, config, content_w, callbacks)
    local fixed = {}
    if model.hint then
        table.insert(fixed, { key = "hint", widget = NoticeBox.build(model.hint, content_w, config, {
            on_retry = callbacks.on_refresh, show_parent = callbacks.show_parent,
        }) })
    end
    local filters = TodosBody.build_filters(model, config, content_w, callbacks)
    if filters then table.insert(fixed, { key = "filters", widget = filters }) end
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

local function layout_key(model, config, viewport_h, content_w, fixed)
    local todos = model.todos or {}
    local fixed_h = 0
    for _, section in ipairs(fixed) do fixed_h = fixed_h + section.widget:getSize().h end
    return table.concat({
        viewport_h, content_w, Theme.scale(config), fixed_h, #fixed,
        todos.total or 0, todos.longest or 0,
        todos.message and 1 or 0, todos.truncated and 1 or 0, todos.partial and 1 or 0,
    }, ":")
end

function TodosBody.build(model, config, width, height, callbacks)
    callbacks = callbacks or {}
    local nav = BottomNav:new{
        tabs = model.nav and model.nav.tabs,
        active = model.nav and model.nav.active,
        config = config,
        plugin_dir = callbacks.plugin_dir,
        on_tab = callbacks.on_nav,
        show_parent = callbacks.show_parent,
    }
    local viewport_h = math.max(1, height - nav:getSize().h)
    local bar = ScrollableContainer:getScrollbarWidth()
    local margin = Theme.margin(config)
    local content_w = math.max(1, width - 2 * margin)
    local preferred = DEFAULT_ROWS
    if preferred > MAX_ROWS then preferred = MAX_ROWS end
    local fixed = build_fixed(model, config, content_w, callbacks)
    local key = layout_key(model, config, viewport_h, content_w, fixed)

    local function model_for(rows, worst_case)
        if type(callbacks.model_for) == "function" then
            return callbacks.model_for(rows, worst_case) or model
        end
        return model
    end

    local probes = 0
    local function measure(rows)
        probes = probes + 1
        local measured_card = TodosBody.build_card(model_for(rows, true), config, content_w, callbacks)
        local fits = assemble(fixed, measured_card, config):getSize().h <= viewport_h
        free(measured_card)
        return { rows = rows, fits = fits }
    end

    local cached = callbacks.layout
    local chosen
    if cached and cached.key == key and cached.rows then
        chosen = { rows = cached.rows, fits = true }
    elseif not model.todos then
        chosen = { rows = preferred, fits = true }
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

    local scroll, filler, viewport, root, card, chosen_model, rows
    if not chosen then
        content_w = math.max(1, width - bar - 2 * margin)
        rows = 1
        chosen_model = model_for(rows)
        for _, section in ipairs(fixed) do free(section.widget) end
        fixed = build_fixed(chosen_model, config, content_w, callbacks)
        card = TodosBody.build_card(chosen_model, config, content_w, callbacks)
        root = assemble(fixed, card, config)
    else
        rows = chosen.rows
        chosen_model = model_for(rows)
        card = TodosBody.build_card(chosen_model, config, content_w, callbacks)
        root = assemble(fixed, card, config)
        local extra = viewport_h - root:getSize().h
        if card and extra > 0 then
            TodosCard.apply_fill(card, card:getSize().h + extra)
            if root.resetLayout then root:resetLayout() end
        end
    end
    local page = LeftContainer:new{ dimen = Geom:new{ w = content_w, h = root:getSize().h }, root }
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, HorizontalSpan:new{ width = Theme.margin(config) })
    table.insert(row, page)
    if not chosen then
        scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = viewport_h },
            row,
        }
        scroll.dialog = callbacks.show_parent
        scroll.show_parent = callbacks.show_parent
        viewport = scroll
    else
        filler = VerticalSpan:new{ width = math.max(0, viewport_h - row:getSize().h) }
        viewport = row
    end

    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, viewport)
    if filler then table.insert(group, filler) end
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
    body.rows = rows
    body.probes = probes
    body.content_width = content_w
    body.fits = scroll == nil
    body.layout = body.fits and { key = key, rows = rows } or nil

    local y = 0
    for index, child in ipairs(root) do
        for _, section in ipairs(fixed) do
            if child == section.widget then body:track_section(section.key, root, index, margin, y) end
        end
        if child == card then body:track_section("card", root, index, margin, y) end
        y = y + child:getSize().h
    end
    if body.fits and chosen_model.todos and (chosen_model.todos.pages or 0) > 1 then
        body:enable_swipe(callbacks.on_next_page, callbacks.on_prev_page)
    end
    return body
end

return TodosBody
