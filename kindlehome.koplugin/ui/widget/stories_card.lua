-- Top Stories card: inverted Y/HN badge, in-card refresh, numbered rows and
-- a binary-inverted pager. Rows per page are configured by the caller
-- (four by default, degraded to fit).
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local TapIcon = require("ui/widget/tap_icon")
local TapRow = require("ui/widget/tap_row")

local StoriesCard = {}

local function build_header(hn, config, content_w, callbacks)
    local row = HorizontalGroup:new{ align = "center" }
    local badge = FrameContainer:new{
        margin = 0,
        padding = Theme.native_size(config, 3),
        bordersize = 0,
        background = Theme.color.inverse_bg,
        TextWidget:new{
            text = hn.badge or "Y/HN",
            face = Theme.face(config, "label_sm", true),
            bold = true,
            fgcolor = Theme.color.inverse_fg,
        },
    }
    local title_widget = DesignText.line(hn.title or "TOP STORIES", config, "label_lg", true)
    local gap = Theme.native_size(config, Theme.space.sm)
    local icon_size = Theme.native_size(config, 22)
    local fixed = badge:getSize().w + gap + title_widget:getSize().w + icon_size

    local label = nil
    local label_gap = 0
    if hn.refreshed and content_w - fixed - 2 * gap >= Theme.native_size(config, 40) then
        label = DesignText.line(hn.refreshed, config, "label_md", false, Theme.color.muted)
        local max_label = math.max(1, content_w - fixed - 2 * gap)
        if label:getSize().w > max_label then label.max_width = max_label end
        label_gap = gap
    end
    local spent = fixed + (label and (label:getSize().w + label_gap) or 0)

    table.insert(row, badge)
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, title_widget)
    table.insert(row, HorizontalSpan:new{ width = math.max(0, content_w - spent) })
    if label then
        table.insert(row, label)
        table.insert(row, HorizontalSpan:new{ width = label_gap })
    end
    table.insert(row, TapIcon:new{
        icon = "cre.render.reload",
        width = icon_size,
        height = icon_size,
        show_parent = callbacks.show_parent,
        on_tap = callbacks.on_refresh,
    })
    return row
end

local function build_row(row, config, content_w, on_open, show_parent)
    local rank_w = Theme.native_size(config, 30)
    local text_w = math.max(1, content_w - rank_w - Theme.native_size(config, Theme.space.sm))
    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, DesignText.box(
        row.title, text_w, config, "headline_md", true))
    table.insert(body, DesignText.span(config, Theme.space.xs))
    table.insert(body, DesignText.box(
        row.meta, text_w, config, "label_md", false, Theme.color.muted))
    local group = HorizontalGroup:new{ align = "top" }
    table.insert(group, LeftContainer:new{
        dimen = Geom:new{ w = rank_w, h = Theme.native_size(config, 18) },
        DesignText.line(tostring(row.rank) .. ".", config, "label_md", true, Theme.color.muted),
    })
    table.insert(group, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.sm) })
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

local function build_pager(hn, config, content_w, callbacks, plugin_dir)
    local label = "Page " .. tostring(hn.page) .. " of " .. tostring(hn.pages)
    local label_widget = DesignText.line(label, config, "label_md", false, Theme.color.muted)
    local icon_size = Theme.native_size(config, 20)
    local button_pad = Theme.native_size(config, 5)
    local button_w = icon_size + 2 * button_pad
    local gap = Theme.native_size(config, Theme.space.sm)
    local row = HorizontalGroup:new{ align = "center" }

    local function build_button(name, fallback_icon, on_tap)
        return FrameContainer:new{
            margin = 0,
            padding = button_pad,
            bordersize = 0,
            background = Theme.color.inverse_bg,
            TapIcon:new{
                icon = fallback_icon,
                file = Theme.icon_file(plugin_dir, "action", name, true),
                width = icon_size,
                height = icon_size,
                alpha = true,
                show_parent = callbacks.show_parent,
                on_tap = on_tap,
            },
        }
    end

    table.insert(row, label_widget)
    table.insert(row, HorizontalSpan:new{
        width = math.max(0, content_w - label_widget:getSize().w - 2 * button_w - gap),
    })
    table.insert(row, build_button("prev", "chevron.left", callbacks.on_prev_page))
    table.insert(row, HorizontalSpan:new{ width = gap })
    table.insert(row, build_button("next", "chevron.right", callbacks.on_next_page))
    return row
end

function StoriesCard.apply_fill(card, fill_height)
    local info = card.fill_info
    if not info or not fill_height then return end
    local content = card[1]
    local gap = fill_height - 2 * (info.border + info.padding) - content:getSize().h
    if gap <= 0 then return end
    if info.has_pager then
        table.insert(content, #content, VerticalSpan:new{ width = gap })
    else
        table.insert(content, VerticalSpan:new{ width = gap })
    end
    if content.resetLayout then content:resetLayout() end
    card.fill_info = nil
end

function StoriesCard.build(hn, config, inner_w, callbacks, plugin_dir, fill_height)
    local border = Theme.hairline(config)
    local padding = Theme.native_size(config, 10)
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local content = VerticalGroup:new{ align = "left" }
    table.insert(content, build_header(hn, config, content_w, callbacks))
    table.insert(content, DesignText.span(config, Theme.space.sm))
    table.insert(content, DesignText.divider(config, content_w))

    if #hn.items == 0 then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box(
            hn.empty or "HN unavailable.", content_w, config, "body_md", false, Theme.color.muted))
    else
        for index, row in ipairs(hn.items) do
            table.insert(content, DesignText.span(config, Theme.space.sm))
            table.insert(content, build_row(row, config, content_w, callbacks.on_open_hn, callbacks.show_parent))
            if index < #hn.items then
                table.insert(content, DesignText.span(config, Theme.space.sm))
                table.insert(content, DesignText.divider(config, content_w))
            end
        end
    end

    if hn.message then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.box(hn.message, content_w, config, "body_sm", false, Theme.color.muted))
    end

    local has_pager = hn.pages > 1
    if has_pager then
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, DesignText.divider(config, content_w))
        table.insert(content, DesignText.span(config, Theme.space.sm))
        table.insert(content, build_pager(hn, config, content_w, callbacks, plugin_dir))
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
    StoriesCard.apply_fill(frame, fill_height)
    return frame
end

return StoriesCard
