-- SPDX-License-Identifier: MIT
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local TapIcon = require("ui/widget/tap_icon")
local TapRow = require("ui/widget/tap_row")

local TodosCard = {}

local TapGlyph = InputContainer:extend{
    text = nil,
    config = nil,
    width = nil,
    on_tap = nil,
    show_parent = nil,
}

function TapGlyph:init()
    self.show_parent = self.show_parent or self
    self[1] = DesignText.line(self.text or "", self.config, "label_md", true)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width or size.w, h = size.h }
    self.ges_events = {
        TapGlyph = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function TapGlyph:onTapGlyph()
    UIManager:setDirty(self.show_parent, "ui")
    if type(self.on_tap) == "function" then self.on_tap() end
    return true
end

local function glyph(text, config, width, on_tap, show_parent)
    return TapGlyph:new{
        text = text, config = config, width = width,
        on_tap = on_tap, show_parent = show_parent,
    }
end

local function icon(name, width, on_tap, show_parent)
    return TapIcon:new{
        icon = name,
        width = width,
        height = width,
        show_parent = show_parent,
        on_tap = on_tap,
    }
end

-- Two-arrow cycle shipped by the plugin; the native "cre.render.reload" is a
-- framed document with a tiny badge, which is unreadable at e-ink sizes.
local function refresh_icon(width, on_tap, show_parent, refresh_file)
    if refresh_file then
        return TapIcon:new{
            file = refresh_file,
            width = width,
            height = width,
            show_parent = show_parent,
            on_tap = on_tap,
        }
    end
    return icon("cre.render.reload", width, on_tap, show_parent)
end

local function details_icon(width, on_tap, show_parent, eye_file)
    if eye_file then
        return TapIcon:new{
            file = eye_file,
            width = width,
            height = width,
            show_parent = show_parent,
            on_tap = on_tap,
        }
    end
    return icon("notice-info", width, on_tap, show_parent)
end

-- KOReader's native "plus" is an outlined appbar icon: its 2/48 stroke reads
-- as a hollow cross at small sizes. Ship a solid '+' instead.
local function plus_icon(width, on_tap, show_parent, plus_file)
    if plus_file then
        return TapIcon:new{
            file = plus_file,
            width = width,
            height = width,
            show_parent = show_parent,
            on_tap = on_tap,
        }
    end
    return icon("plus", width, on_tap, show_parent)
end

local function build_header(model, config, content_w, callbacks, plus_file)
    local row = HorizontalGroup:new{ align = "center" }
    local badge = FrameContainer:new{
        margin = 0,
        padding = Theme.native_size(config, 3),
        bordersize = 0,
        background = Theme.color.inverse_bg,
        DesignText.line(model.badge or "TODO", config, "label_sm", true, Theme.color.inverse_fg),
    }
    local title = DesignText.line(model.title or "TASKS", config, "label_lg", true)
    local gap = Theme.native_size(config, Theme.space.sm)
    local add_w = Theme.native_size(config, 30)
    local refresh_w = Theme.native_size(config, 22)
    local has_refresh = type(callbacks.on_refresh) == "function"
    local icon_space = add_w + (has_refresh and refresh_w + gap or 0)
    local used = badge:getSize().w + gap + title:getSize().w + icon_space
    local refresh_file = callbacks.plugin_dir
        and Theme.icon_file(callbacks.plugin_dir, "action", "refresh") or nil
    table.insert(row, badge)
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, title)
    table.insert(row, HorizontalSpan:new{ width = math.max(0, content_w - used) })
    if has_refresh then
        table.insert(row, refresh_icon(refresh_w, callbacks.on_refresh, callbacks.show_parent, refresh_file))
        table.insert(row, HorizontalSpan:new{ width = gap })
    end
    table.insert(row, plus_icon(add_w, callbacks.on_add, callbacks.show_parent, plus_file))
    return row
end

local function build_task_row(task, config, content_w, callbacks, eye_file)
    local check_w = Theme.native_size(config, 28)
    local delete_w = Theme.native_size(config, 20)
    local info_w = Theme.native_size(config, 18)
    local gap = Theme.native_size(config, Theme.space.sm)
    local text_w = math.max(1, content_w - check_w - delete_w - 2 * info_w - 5 * gap)
    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, DesignText.box(task.title, text_w, config, "headline_md", true))
    table.insert(body, DesignText.span(config, Theme.space.xs))
    table.insert(body, DesignText.box(task.meta, text_w, config, "label_md", false, Theme.color.muted))
    if task.detail_preview then
        table.insert(body, DesignText.span(config, Theme.space.xs))
        table.insert(body, DesignText.box(task.detail_preview, text_w, config, "body_sm", false, Theme.color.muted))
    end
    local content = LeftContainer:new{
        dimen = Geom:new{ w = text_w, h = body:getSize().h },
        body,
    }
    local row = HorizontalGroup:new{ align = "top" }
    table.insert(row, glyph(task.done and "[x]" or "[ ]", config, check_w, function()
        callbacks.on_toggle(task.id)
    end, callbacks.show_parent))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, TapRow:new{
        content_group = content,
        show_parent = callbacks.show_parent,
        on_tap = task.id and function() callbacks.on_rename(task.id) end or nil,
    })
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, details_icon(info_w, function()
        callbacks.on_details(task.id)
    end, callbacks.show_parent, eye_file))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, icon("edit", info_w, function()
        callbacks.on_edit_details(task.id)
    end, callbacks.show_parent))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, glyph("x", config, delete_w, function()
        callbacks.on_delete(task.id)
    end, callbacks.show_parent))
    return row
end

local function build_pager(model, config, content_w, callbacks)
    local label = "Page " .. tostring(model.page) .. " of " .. tostring(model.pages)
    local label_widget = DesignText.line(label, config, "label_md", false, Theme.color.muted)
    local button_w = Theme.native_size(config, 24)
    local gap = Theme.native_size(config, Theme.space.sm)
    local row = HorizontalGroup:new{ align = "center" }
    table.insert(row, label_widget)
    table.insert(row, HorizontalSpan:new{
        width = math.max(0, content_w - label_widget:getSize().w - 2 * button_w - gap),
    })
    table.insert(row, glyph("<", config, button_w, callbacks.on_prev_page, callbacks.show_parent))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, glyph(">", config, button_w, callbacks.on_next_page, callbacks.show_parent))
    return row
end

function TodosCard.apply_fill(card, fill_height)
    local info = card.fill_info
    if not info or not fill_height then return end
    local content = card[1]
    local gap = fill_height - 2 * (info.border + info.padding) - content:getSize().h
    if gap <= 0 then return end
    if info.has_pager then
        -- Keep the pager row bottom-anchored inside the taller card.
        table.insert(content, #content, VerticalSpan:new{ width = gap })
    else
        table.insert(content, VerticalSpan:new{ width = gap })
    end
    if content.resetLayout then content:resetLayout() end
    card.fill_info = nil
end

function TodosCard.build(model, config, inner_w, callbacks, fill_height)
    local border = Theme.hairline(config)
    local padding = Theme.native_size(config, 10)
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local eye_file = callbacks.plugin_dir
        and Theme.icon_file(callbacks.plugin_dir, "action", "eye") or nil
    local plus_file = callbacks.plugin_dir
        and Theme.icon_file(callbacks.plugin_dir, "action", "plus") or nil
    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, build_header(model, config, content_w, callbacks, plus_file))
    table.insert(content, DesignText.span(config, Theme.space.sm))
    table.insert(content, DesignText.divider(config, content_w))

    if #model.items == 0 then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box(
            model.empty or "No tasks.", content_w, config, "body_md", false, Theme.color.muted))
    else
        for index, task in ipairs(model.items) do
            table.insert(content, DesignText.span(config, Theme.space.sm))
            table.insert(content, build_task_row(task, config, content_w, callbacks, eye_file))
            if index < #model.items then
                table.insert(content, DesignText.span(config, Theme.space.sm))
                table.insert(content, DesignText.divider(config, content_w))
            end
        end
    end

    if model.message then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box(model.message, content_w, config, "body_sm", false, Theme.color.muted))
    end
    if model.truncated then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box("Server trimmed the task list at 128 KiB.", content_w, config, "body_sm", false, Theme.color.muted))
    end
    if model.partial then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box("Showing the first tasks; the list is large. Refresh to load more.", content_w, config, "body_sm", false, Theme.color.muted))
    end

    if model.pages > 1 then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.divider(config, content_w))
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, build_pager(model, config, content_w, callbacks))
    end

    local frame = FrameContainer:new{
        margin = 0,
        padding = padding,
        bordersize = border,
        color = Theme.color.hairline,
        background = Theme.color.canvas,
        content,
    }
    frame.fill_info = { border = border, padding = padding, has_pager = model.pages > 1 }
    TodosCard.apply_fill(frame, fill_height)
    return frame
end

return TodosCard
