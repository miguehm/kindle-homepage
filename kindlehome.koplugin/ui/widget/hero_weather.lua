-- SPDX-License-Identifier: MIT
-- Combined clock/status + weather card. Two columns on the 6.8" portrait
-- canvas, separated by a single vertical hairline.
--
-- Left: clock, date and device status. Right: a compact weather summary
-- (icon + temperature, condition · place, range · wind · humidity, tomorrow).
-- Freshness lives in the Top Stories header only, so a clock tick repaints
-- this card alone.
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")
local BatteryGlyph = require("ui/widget/battery_glyph")

local HeroWeather = {}

local function join_parts(parts)
    local out = {}
    for _, part in ipairs(parts) do
        if part and part ~= "" then out[#out + 1] = part end
    end
    return table.concat(out, " · ")
end

local function left_aligned(widget, width)
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = widget:getSize().h }, widget,
    }
end

local function build_left(hero, config, width)
    local group = VerticalGroup:new{ align = "left" }
    local clock_row = HorizontalGroup:new{ align = "bottom" }
    table.insert(clock_row, DesignText.line(hero.clock, config, "display", true))
    if hero.meridiem then
        table.insert(clock_row, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.xs) })
        table.insert(clock_row, DesignText.line(hero.meridiem, config, "label_lg", false, Theme.color.muted))
    end
    table.insert(group, left_aligned(clock_row, width))
    table.insert(group, DesignText.span(config, Theme.space.xs))
    table.insert(group, DesignText.line_fit(hero.date_short, width, config, "label_md", true))

    -- Without a stories card there is no card header for the indicator.
    if hero.refreshing then
        table.insert(group, DesignText.span(config, Theme.space.xs))
        table.insert(group, DesignText.line_fit("Updating…", width, config, "label_md", false,
            Theme.color.muted))
    end

    local icons = HorizontalGroup:new{ align = "center" }
    if hero.show_network then
        local wifi = Theme.native_size(config, Theme.space.gutter)
        table.insert(icons, IconWidget:new{
            icon = hero.wifi and "wifi.secure.100" or "wifi.open.0",
            width = wifi,
            height = wifi,
        })
        table.insert(icons, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.sm) })
    end
    if hero.show_battery and hero.battery_pct then
        table.insert(icons, BatteryGlyph:new{
            config = config, capacity = hero.battery_pct, charging = hero.charging,
        })
        table.insert(icons, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.xs) })
        table.insert(icons, DesignText.line(
            tostring(math.floor(hero.battery_pct + 0.5)) .. "%" .. (hero.charging and " CHG" or ""),
            config, "label_md", false, Theme.color.muted))
    end
    if #icons > 0 then
        table.insert(group, DesignText.span(config, Theme.space.sm))
        table.insert(group, left_aligned(icons, width))
    end
    return group
end

local function build_right(weather, config, width, plugin_dir)
    local group = VerticalGroup:new{ align = "left" }
    local icon_size = Theme.px(config, "icon_lg")
    local gap = Theme.native_size(config, Theme.space.sm)
    local top = HorizontalGroup:new{ align = "center" }
    table.insert(top, IconWidget:new{
        icon = "notice-info",
        file = Theme.icon_file(plugin_dir, "weather", weather.icon),
        width = icon_size,
        height = icon_size,
    })
    if weather.temp then
        table.insert(top, HorizontalSpan:new{ width = gap })
        table.insert(top, DesignText.line(weather.temp, config, "headline_lg", true))
    end
    table.insert(group, left_aligned(top, width))

    local summary = join_parts({ weather.condition, weather.place })
    if summary ~= "" then
        table.insert(group, DesignText.span(config, Theme.space.xs))
        table.insert(group, DesignText.line_fit(summary, width, config, "body_md", false))
    end
    local details = join_parts({
        (weather.hi or weather.lo) and ("H " .. (weather.hi or "–") .. " · L " .. (weather.lo or "–")) or nil,
        weather.wind,
        weather.humidity,
    })
    if details ~= "" then
        table.insert(group, DesignText.box_lines(details, width, config, "label_md", false,
            Theme.color.muted, 2))
    end
    if weather.tomorrow and (weather.tomorrow.hi or weather.tomorrow.lo) then
        local small = Theme.px(config, "icon_sm")
        local xs = Theme.native_size(config, Theme.space.xs)
        table.insert(group, DesignText.span(config, Theme.space.xs))
        table.insert(group, DesignText.divider(config, width))
        table.insert(group, DesignText.span(config, Theme.space.xs))
        local tomorrow = HorizontalGroup:new{ align = "center" }
        table.insert(tomorrow, DesignText.line("Tomorrow", config, "label_md", true))
        table.insert(tomorrow, HorizontalSpan:new{ width = gap })
        table.insert(tomorrow, IconWidget:new{
            icon = "notice-info",
            file = Theme.icon_file(plugin_dir, "weather", weather.tomorrow.icon),
            width = small,
            height = small,
        })
        table.insert(tomorrow, HorizontalSpan:new{ width = xs })
        table.insert(tomorrow, DesignText.line(
            (weather.tomorrow.hi or "–") .. " / " .. (weather.tomorrow.lo or "–"),
            config, "label_md", false))
        table.insert(group, left_aligned(tomorrow, width))
    end
    if weather.fallback then
        table.insert(group, DesignText.box(weather.fallback, width, config, "body_sm", false, Theme.color.muted))
    end
    if weather.message then
        table.insert(group, DesignText.box(weather.message, width, config, "body_sm", false, Theme.color.muted))
    end
    return group
end

function HeroWeather.build(hero, config, inner_w, weather, plugin_dir)
    local border = Theme.hairline(config)
    local padding = Theme.px(config, "card_pad")
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local gap = Theme.native_size(config, Theme.space.gutter)
    local usable_w = math.max(1, content_w - 2 * gap - border)
    local left_w = weather and math.floor(usable_w * 0.45) or usable_w
    local right_w = usable_w - left_w

    local left = build_left(hero, config, left_w)
    local content = HorizontalGroup:new{ align = "top" }
    if weather then
        local right = build_right(weather, config, right_w, plugin_dir)
        local height = math.max(left:getSize().h, right:getSize().h)
        table.insert(content, left_aligned(left, left_w))
        table.insert(content, HorizontalSpan:new{ width = gap })
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = border, h = height },
            background = Theme.color.hairline,
        })
        table.insert(content, HorizontalSpan:new{ width = gap })
        table.insert(content, left_aligned(right, right_w))
    else
        table.insert(content, left_aligned(left, left_w))
    end
    return FrameContainer:new{
        margin = 0,
        padding = padding,
        bordersize = border,
        color = Theme.color.hairline,
        background = Theme.color.canvas,
        content,
    }
end

return HeroWeather
