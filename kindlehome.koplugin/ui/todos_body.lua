-- SPDX-License-Identifier: MIT
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local BottomNav = require("ui/widget/bottom_nav")
local TagChips = require("ui/widget/tag_chips")
local TodosCard = require("ui/widget/todos_card")

local TodosBody = {}

local SECTION_GAP = 8
local DEFAULT_ROWS = 6
local MAX_ROWS = 10

local BodyWrapper = InputContainer:extend{}

function BodyWrapper:getCropRegion()
    if self.scroll and type(self.scroll.getCropRegion) == "function" then
        return self.scroll:getCropRegion()
    end
    return self.dimen
end

local function build_sections(model, config, content_w, callbacks)
    local sections = {}
    if model.hint then
        table.insert(sections, DesignText.box(
            model.hint, content_w, config, "body_sm", false, Theme.color.muted))
    end
    if model.todos then
        local chips = TagChips.build(model.todos, config, content_w, {
            on_tag = callbacks.on_tag,
            on_tag_doc = callbacks.on_tag_doc,
            show_parent = callbacks.show_parent,
        })
        if chips then table.insert(sections, chips) end
        table.insert(sections, TodosCard.build(model.todos, config, content_w, callbacks))
    end
    return sections
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

local function build_page(measured_model, config, content_w, callbacks)
    local root = assemble(build_sections(measured_model, config, content_w, callbacks), config)
    local page = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = root:getSize().h },
        root,
    }
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, HorizontalSpan:new{ width = Theme.margin(config) })
    table.insert(row, page)
    return page, root, row
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
    if preferred < 1 then preferred = 1 end
    if preferred > MAX_ROWS then preferred = MAX_ROWS end

    local probes = 0
    local function measure(rows)
        probes = probes + 1
        local measured_model = model
        if type(callbacks.model_for) == "function" then
            measured_model = callbacks.model_for(rows) or model
        end
        local page, root, row = build_page(measured_model, config, content_w, callbacks)
        return {
            rows = rows, model = measured_model, page = page, root = root, row = row,
            fits = root:getSize().h <= viewport_h,
        }
    end

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

    local scroll = nil
    local filler = nil
    local viewport
    if not chosen then
        content_w = math.max(1, width - bar - 2 * margin)
        chosen = measure(1)
        scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = width, h = viewport_h },
            chosen.row,
        }
        scroll.dialog = callbacks.show_parent
        scroll.show_parent = callbacks.show_parent
        viewport = scroll
    else
        filler = VerticalSpan:new{ width = math.max(0, viewport_h - chosen.row:getSize().h) }
        viewport = chosen.row
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
    body.page = chosen.page
    body.model = chosen.model
    body.rows = chosen.rows
    body.probes = probes
    body.content_width = content_w
    body.fits = scroll == nil
    return body
end

return TodosBody
