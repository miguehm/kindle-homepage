-- Combined clock/status + weather card (DESIGN.md hero). Two columns on the
-- 6.8" portrait canvas, separated by a single vertical hairline.
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

local function build_left(hero, config, width)
    local group = VerticalGroup:new{ align = "left" }
    local clock_row = HorizontalGroup:new{ align = "bottom" }
    table.insert(clock_row, DesignText.line(hero.clock, config, "display", true))
    if hero.meridiem then
        table.insert(clock_row, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.xs) })
        table.insert(clock_row, DesignText.line(hero.meridiem, config, "label_lg", false, Theme.color.muted))
    end
    table.insert(group, LeftContainer:new{
        dimen = Geom:new{ w = width, h = clock_row:getSize().h }, clock_row,
    })
    table.insert(group, DesignText.span(config, Theme.space.xs))
    table.insert(group, DesignText.line(hero.date_short, config, "label_md", true))
    table.insert(group, DesignText.span(config, Theme.space.sm))

    local status = {}
    if hero.updated_clock then
        table.insert(status, hero.updated_clock .. " · " .. (hero.stale and "Cached" or "Updated"))
    end
    local status_line = DesignText.box(join_parts(status), width, config, "label_md", false, Theme.color.muted)
    table.insert(group, status_line)

    local icons = HorizontalGroup:new{ align = "center" }
    if hero.show_network then
        table.insert(icons, IconWidget:new{
            icon = hero.wifi and "wifi.secure.100" or "wifi.open.0",
            width = Theme.native_size(config, 14),
            height = Theme.native_size(config, 14),
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
        table.insert(group, DesignText.span(config, Theme.space.xs))
        table.insert(group, LeftContainer:new{
            dimen = Geom:new{ w = width, h = icons:getSize().h }, icons,
        })
    end
    return group
end

local function build_right(weather, config, width, plugin_dir)
    local group = VerticalGroup:new{ align = "left" }
    local top = HorizontalGroup:new{ align = "center" }
    table.insert(top, IconWidget:new{
        icon = "notice-info",
        file = Theme.icon_file(plugin_dir, "weather", weather.icon),
        width = Theme.native_size(config, 28),
        height = Theme.native_size(config, 28),
    })
    table.insert(top, HorizontalSpan:new{ width = Theme.native_size(config, Theme.space.sm) })
    if weather.temp then
        table.insert(top, DesignText.line(weather.temp, config, "headline_lg", true))
    end
    if #top > 0 then
        table.insert(group, LeftContainer:new{
            dimen = Geom:new{ w = width, h = top:getSize().h }, top,
        })
    end
    if weather.condition then
        table.insert(group, DesignText.box(weather.condition, width, config, "body_md"))
    end
    local range = join_parts({ weather.hi and "H:" .. weather.hi or nil, weather.lo and "L:" .. weather.lo or nil })
    if range ~= "" then
        table.insert(group, DesignText.box(range, width, config, "body_sm", false, Theme.color.muted))
    end
    if weather.place then
        table.insert(group, DesignText.box(weather.place, width, config, "body_md", true))
    end
    if weather.wind then
        table.insert(group, DesignText.box("Wind: " .. weather.wind, width, config, "body_sm", false, Theme.color.muted))
    end
    if weather.humidity then
        table.insert(group, DesignText.box("Humidity: " .. weather.humidity, width, config, "body_sm", false, Theme.color.muted))
    end
    if weather.tomorrow and (weather.tomorrow.hi or weather.tomorrow.lo) then
        table.insert(group, DesignText.span(config, Theme.space.xs))
        table.insert(group, DesignText.divider(config, width))
        table.insert(group, DesignText.span(config, Theme.space.xs))
        local icon_size = Theme.native_size(config, 18)
        local gap = Theme.native_size(config, Theme.space.xs)
        local tomorrow = HorizontalGroup:new{ align = "center" }
        table.insert(tomorrow, IconWidget:new{
            icon = "notice-info",
            file = Theme.icon_file(plugin_dir, "weather", weather.tomorrow.icon),
            width = icon_size,
            height = icon_size,
        })
        table.insert(tomorrow, HorizontalSpan:new{ width = gap })
        table.insert(tomorrow, DesignText.box(
            "Tomorrow  " .. (weather.tomorrow.hi or "n/a") .. " / " .. (weather.tomorrow.lo or "n/a"),
            math.max(1, width - icon_size - gap), config, "label_sm", false))
        table.insert(group, LeftContainer:new{
            dimen = Geom:new{ w = width, h = tomorrow:getSize().h }, tomorrow,
        })
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
    local padding = Theme.native_size(config, 12)
    local content_w = math.max(1, inner_w - 2 * (border + padding))
    local gap = Theme.native_size(config, 16)
    local usable_w = math.max(1, content_w - 2 * gap - border)
    local left_w = weather and math.floor(usable_w * 0.55) or usable_w
    local right_w = usable_w - left_w

    local left = build_left(hero, config, left_w)
    local content = HorizontalGroup:new{ align = "top" }
    table.insert(content, LeftContainer:new{
        dimen = Geom:new{ w = left_w, h = left:getSize().h }, left,
    })
    if weather then
        local right = build_right(weather, config, right_w, plugin_dir)
        local height = math.max(left:getSize().h, right:getSize().h)
        table.insert(content, HorizontalSpan:new{ width = gap })
        table.insert(content, LineWidget:new{
            dimen = Geom:new{ w = border, h = height },
            background = Theme.color.hairline,
        })
        table.insert(content, HorizontalSpan:new{ width = gap })
        table.insert(content, LeftContainer:new{
            dimen = Geom:new{ w = right_w, h = right:getSize().h }, right,
        })
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
