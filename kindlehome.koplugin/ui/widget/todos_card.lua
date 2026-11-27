-- SPDX-License-Identifier: MIT
-- TASKS card: inverted TODO badge, refresh and add actions, a small date/time
-- line, task rows and the shared bottom-anchored pager.
--
-- Every control is a 48dp touch slot: the checkbox, the row body (opens the
-- editor), details (eye), edit and delete. Rows invert while their action
-- runs (press_feedback.lua).
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local Checkbox = require("ui/widget/checkbox")
local DesignText = require("ui/widget/design_text")
local NoticeBox = require("ui/widget/notice_box")
local Pager = require("ui/widget/pager")
local TapIcon = require("ui/widget/tap_icon")
local TapRow = require("ui/widget/tap_row")

local TodosCard = {}

local TITLE_LINES = 2
local PREVIEW_LINES = 2

local function icon(config, file, fallback, size, on_tap, show_parent)
    return TapIcon:new{
        icon = (not file) and fallback or nil,
        file = file,
        width = size,
        height = size,
        config = config,
        show_parent = show_parent,
        on_tap = on_tap,
    }
end

local function badge(text, config)
    return FrameContainer:new{
        margin = 0,
        padding = Theme.px(config, "badge_pad"),
        bordersize = 0,
        background = Theme.color.inverse_bg,
        DesignText.line(text, config, "label_sm", true, Theme.color.inverse_fg),
    }
end

local function build_header(model, config, content_w, callbacks)
    local row = HorizontalGroup:new{ align = "center" }
    local todo_badge = badge(model.badge or "TODO", config)
    local title = DesignText.line(model.title or "TASKS", config, "label_lg", true)
    local gap = Theme.native_size(config, Theme.space.sm)
    local plugin_dir = callbacks.plugin_dir
    -- Two-arrow cycle shipped by the plugin; the native "cre.render.reload"
    -- is a framed document with a tiny badge, unreadable at e-ink sizes.
    local refresh_file = plugin_dir and Theme.icon_file(callbacks.plugin_dir, "action", "refresh") or nil
    -- KOReader's native "plus" is an outlined appbar icon: its 2/48 stroke
    -- reads as a hollow cross at small sizes. Ship a solid '+' instead, a
    -- size up from the row icons because it is the primary action.
    local plus_file = plugin_dir and Theme.icon_file(callbacks.plugin_dir, "action", "plus") or nil
    local refresh = nil
    if type(callbacks.on_refresh) == "function" then
        refresh = icon(config, refresh_file, "cre.render.reload", Theme.px(config, "icon"),
            callbacks.on_refresh, callbacks.show_parent)
    end
    local add = icon(config, plus_file, "plus", Theme.px(config, "icon_lg"),
        callbacks.on_add, callbacks.show_parent)
    local status = model.refreshing and badge("Updating…", config) or nil

    local used = todo_badge:getSize().w + gap + title:getSize().w + add:getSize().w
        + (refresh and refresh:getSize().w or 0)
        + (status and (status:getSize().w + gap) or 0)
    table.insert(row, todo_badge)
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, title)
    table.insert(row, HorizontalSpan:new{ width = math.max(0, content_w - used) })
    if status then
        table.insert(row, status)
        table.insert(row, HorizontalSpan:new{ width = gap })
    end
    if refresh then table.insert(row, refresh) end
    table.insert(row, add)
    row.refresh_button = refresh
    row.add_button = add
    return row
end

local function build_task_row(task, config, content_w, callbacks)
    local plugin_dir = callbacks.plugin_dir
    local glyph = Theme.px(config, "icon_sm")
    local show_parent = callbacks.show_parent
    local check = Checkbox:new{
        checked = task.done,
        config = config,
        show_parent = show_parent,
        on_tap = function() callbacks.on_toggle(task.id) end,
    }
    local eye_file = plugin_dir and Theme.icon_file(callbacks.plugin_dir, "action", "eye") or nil
    local eye = icon(config, eye_file, "notice-info", glyph,
        function() callbacks.on_details(task.id) end, show_parent)
    local edit = icon(config, plugin_dir and Theme.icon_file(plugin_dir, "action", "edit") or nil,
        "edit", glyph, function() callbacks.on_edit_details(task.id) end, show_parent)
    local delete = icon(config, plugin_dir and Theme.icon_file(plugin_dir, "action", "delete") or nil,
        "close", glyph, function() callbacks.on_delete(task.id) end, show_parent)

    local text_w = math.max(1, content_w - check:getSize().w - eye:getSize().w
        - edit:getSize().w - delete:getSize().w)
    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, DesignText.box_lines(task.title, text_w, config, "headline_sm", true,
        task.done and Theme.color.muted or nil, TITLE_LINES))
    table.insert(body, DesignText.span(config, Theme.space.xs))
    table.insert(body, DesignText.line_fit(task.meta, text_w, config, "label_md", false, Theme.color.muted))
    if task.detail_preview then
        table.insert(body, DesignText.span(config, Theme.space.xs))
        table.insert(body, DesignText.box_lines(task.detail_preview, text_w, config, "body_sm", false,
            Theme.color.muted, PREVIEW_LINES))
    end
    local content = LeftContainer:new{
        dimen = Geom:new{ w = text_w, h = math.max(body:getSize().h, check:getSize().h) },
        body,
    }
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, check)
    table.insert(row, TapRow:new{
        content_group = content,
        show_parent = show_parent,
        on_tap = task.id and function() callbacks.on_rename(task.id) end or nil,
    })
    table.insert(row, eye)
    table.insert(row, edit)
    table.insert(row, delete)
    return row
end

function TodosCard.apply_fill(card, fill_height)
    local info = card.fill_info
    if not info or not fill_height then return end
    local content = card[1]
    local gap = fill_height - 2 * (info.border + info.padding) - content:getSize().h
    if gap <= 0 then return end
    if info.has_pager then
        -- Keep the divider + pager pair bottom-anchored inside the taller card.
        table.insert(content, #content - 1, VerticalSpan:new{ width = gap })
    else
        table.insert(content, VerticalSpan:new{ width = gap })
    end
    if content.resetLayout then content:resetLayout() end
    card.fill_info = nil
end

local function notice(content, text, content_w, config)
    table.insert(content, DesignText.span(config, Theme.space.sm))
    table.insert(content, NoticeBox.build(text, content_w, config))
end

function TodosCard.build(model, config, inner_w, callbacks, fill_height)
    local border = Theme.hairline(config)
    local padding = Theme.px(config, "card_pad")
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local content = VerticalGroup:new{ align = "left" }
    local header = build_header(model, config, content_w, callbacks)
    table.insert(content, header)
    if model.clock_line and model.clock_line ~= "" then
        table.insert(content, DesignText.line_fit(model.clock_line, content_w, config, "label_sm", false,
            Theme.color.muted))
    end
    table.insert(content, DesignText.span(config, Theme.space.xs))
    table.insert(content, DesignText.divider(config, content_w))

    if #model.items == 0 then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box(
            model.empty or "No tasks.", content_w, config, "body_md", false, Theme.color.muted))
    else
        for index, task in ipairs(model.items) do
            table.insert(content, build_task_row(task, config, content_w, callbacks))
            if index < #model.items then
                table.insert(content, DesignText.divider(config, content_w))
            end
        end
    end

    if model.message then notice(content, model.message, content_w, config) end
    if model.truncated then notice(content, "Server trimmed the task list at 128 KiB.", content_w, config) end
    if model.partial then
        notice(content, "Showing the first tasks; the list is large. Refresh to load more.", content_w, config)
    end

    local has_pager = (model.pages or 0) > 1
    local pager = nil
    if has_pager then
        pager = Pager.build(model.page, model.pages, config, content_w, {
            on_prev_page = callbacks.on_prev_page,
            on_next_page = callbacks.on_next_page,
            show_parent = callbacks.show_parent,
        }, callbacks.plugin_dir)
        table.insert(content, DesignText.divider(config, content_w))
        table.insert(content, pager)
    end

    local frame = FrameContainer:new{
        margin = 0,
        padding = padding,
        bordersize = border,
        color = Theme.color.hairline,
        background = Theme.color.canvas,
        content,
    }
    frame.fill_info = { border = border, padding = padding, has_pager = has_pager }
    frame.header = header
    frame.pager = pager
    TodosCard.apply_fill(frame, fill_height)
    return frame
end

return TodosCard
