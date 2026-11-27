-- SPDX-License-Identifier: MIT
-- Top Stories card: inverted Y/HN badge, freshness label (or an inverted
-- "Updating…" badge while an explicit refresh runs), in-card refresh,
-- numbered rows and the shared bottom-anchored pager.
--
-- Rows have a bounded height (title ≤ 2 lines, meta = 1 line), so the row
-- count measured on the longest titles fits every page and paging never
-- changes the layout.
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local NoticeBox = require("ui/widget/notice_box")
local Pager = require("ui/widget/pager")
local TapIcon = require("ui/widget/tap_icon")
local TapRow = require("ui/widget/tap_row")

local StoriesCard = {}

local TITLE_LINES = 2

local function badge(text, config)
    return FrameContainer:new{
        margin = 0,
        padding = Theme.px(config, "badge_pad"),
        bordersize = 0,
        background = Theme.color.inverse_bg,
        DesignText.line(text, config, "label_sm", true, Theme.color.inverse_fg),
    }
end

-- Two-arrow cycle shipped by the plugin; the native "cre.render.reload" is a
-- framed document with a tiny badge, which is unreadable at e-ink sizes.
local function refresh_icon(config, on_refresh, show_parent, plugin_dir)
    local glyph = Theme.px(config, "icon")
    local refresh_file = plugin_dir and Theme.icon_file(plugin_dir, "action", "refresh") or nil
    return TapIcon:new{
        icon = (not refresh_file) and "cre.render.reload" or nil,
        file = refresh_file,
        width = glyph,
        height = glyph,
        config = config,
        show_parent = show_parent,
        on_tap = on_refresh,
    }
end

local function build_header(hn, config, content_w, callbacks, plugin_dir)
    local row = HorizontalGroup:new{ align = "center" }
    local hn_badge = badge(hn.badge or "Y/HN", config)
    local title_widget = DesignText.line(hn.title or "TOP STORIES", config, "label_lg", true)
    local gap = Theme.native_size(config, Theme.space.sm)
    local refresh = refresh_icon(config, callbacks.on_refresh, callbacks.show_parent, plugin_dir)
    local fixed = hn_badge:getSize().w + gap + title_widget:getSize().w + refresh:getSize().w

    local status = nil
    local room = content_w - fixed - 2 * gap
    if hn.refreshing then
        status = badge("Updating…", config)
    elseif hn.refreshed and room >= Theme.native_size(config, 40) then
        status = DesignText.line_fit(hn.refreshed, room, config, "label_md", false, Theme.color.muted)
    end
    local spent = fixed + (status and (status:getSize().w + gap) or 0)

    table.insert(row, hn_badge)
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, title_widget)
    table.insert(row, HorizontalSpan:new{ width = math.max(0, content_w - spent) })
    if status then
        table.insert(row, status)
        table.insert(row, HorizontalSpan:new{ width = gap })
    end
    table.insert(row, refresh)
    row.refresh_button = refresh
    return row
end

local function build_row(row, config, content_w, on_open, show_parent)
    local rank_w = Theme.px(config, "rank_col")
    local text_w = math.max(1, content_w - rank_w)
    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, DesignText.box_lines(
        row.title, text_w, config, "headline_sm", true, nil, TITLE_LINES))
    table.insert(body, DesignText.span(config, Theme.space.xs))
    table.insert(body, DesignText.line_fit(
        row.meta, text_w, config, "label_md", false, Theme.color.muted))
    local rank = DesignText.line(tostring(row.rank) .. ".", config, "label_md", true, Theme.color.muted)
    local group = HorizontalGroup:new{ align = "top" }
    table.insert(group, LeftContainer:new{
        dimen = Geom:new{ w = rank_w, h = rank:getSize().h }, rank,
    })
    table.insert(group, body)
    local content = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = group:getSize().h }, group,
    }
    return TapRow:new{
        content_group = content,
        show_parent = show_parent,
        on_tap = row.id and function() on_open(row.id) end or nil,
    }
end

function StoriesCard.apply_fill(card, fill_height)
    local info = card.fill_info
    if not info or not fill_height then return end
    local content = card[1]
    local gap = fill_height - 2 * (info.border + info.padding) - content:getSize().h
    if gap <= 0 then return end
    if info.has_pager then
        -- Keep the divider + pager pair bottom-anchored.
        table.insert(content, #content - 1, VerticalSpan:new{ width = gap })
    else
        table.insert(content, VerticalSpan:new{ width = gap })
    end
    if content.resetLayout then content:resetLayout() end
    card.fill_info = nil
end

function StoriesCard.build(hn, config, inner_w, callbacks, plugin_dir, fill_height)
    local border = Theme.hairline(config)
    local padding = Theme.px(config, "card_pad")
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local content = VerticalGroup:new{ align = "left" }
    local header = build_header(hn, config, content_w, callbacks, plugin_dir)
    table.insert(content, header)
    table.insert(content, DesignText.span(config, Theme.space.xs))
    table.insert(content, DesignText.divider(config, content_w))

    if #hn.items == 0 then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        if hn.empty_kind == "error" then
            table.insert(content, NoticeBox.build(hn.empty, content_w, config, {
                on_retry = callbacks.on_refresh, show_parent = callbacks.show_parent,
            }))
        else
            table.insert(content, DesignText.box(
                hn.empty or "No stories.", content_w, config, "body_md", false, Theme.color.muted))
        end
    else
        for index, row in ipairs(hn.items) do
            table.insert(content, DesignText.span(config, Theme.space.sm))
            table.insert(content, build_row(row, config, content_w, callbacks.on_open_hn, callbacks.show_parent))
            table.insert(content, DesignText.span(config, Theme.space.sm))
            if index < #hn.items then
                table.insert(content, DesignText.divider(config, content_w))
            end
        end
    end

    if hn.message then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, NoticeBox.build(hn.message, content_w, config))
    end

    local has_pager = (hn.pages or 0) > 1
    local pager = nil
    if has_pager then
        pager = Pager.build(hn.page, hn.pages, config, content_w, {
            on_prev_page = callbacks.on_prev_page,
            on_next_page = callbacks.on_next_page,
            show_parent = callbacks.show_parent,
        }, plugin_dir)
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
    StoriesCard.apply_fill(frame, fill_height)
    return frame
end

return StoriesCard
