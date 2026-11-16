local DashboardModel = {}

local PAGE_SIZE = 5

local function fmt_temp(value)
    if type(value) ~= "number" then return nil end
    return tostring(math.floor(value + 0.5)) .. "°C"
end

local function fmt_int(value)
    if type(value) ~= "number" then return nil end
    return tostring(math.floor(value + 0.5))
end

local function non_empty(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

-- Local timezone offset in seconds east of UTC, computed at `now`.
local function local_offset(now)
    local ok, utc_fields = pcall(os.date, "!*t", now)
    if not ok or not utc_fields then return 0 end
    local as_utc = os.time(utc_fields)
    if type(as_utc) ~= "number" then return 0 end
    return now - as_utc
end

-- hnmd publishes RFC3339 timestamps. Lua 5.1 has no ISO parser, so accept the
-- common forms (`...Z`, `...+02:00`, optional seconds/fractions) and return nil
-- for anything else; callers simply omit the age rather than guessing.
function DashboardModel.parse_time(value)
    if type(value) ~= "string" then return nil end
    local date_part, time_part = value:match("^(%d%d%d%d%-%d%d%-%d%d)[Tt ](%d%d:%d%d)")
    if not date_part or not time_part then return nil end
    local y, m, d = date_part:match("^(%d+)%-(%d+)%-(%d+)")
    local hour, minute = time_part:match("^(%d+):(%d+)")
    if not (y and m and d and hour and minute) then return nil end
    local rest = value:sub(#date_part + 1 + #time_part + 1)
    local second = tonumber(rest:match("^:(%d%d)") or "0") or 0
    local sign, oh, om = rest:match("([%+%-])(%d%d):?(%d%d)")
    local offset = 0
    if sign then
        offset = ((tonumber(oh) or 0) * 60 + (tonumber(om) or 0)) * 60
        if sign == "-" then offset = -offset end
    end
    local ok, t = pcall(os.time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(hour), min = tonumber(minute), sec = second,
    })
    if not ok or type(t) ~= "number" then return nil end
    return t + local_offset(t) - offset
end

local function fmt_age(published_at, now)
    local ts = DashboardModel.parse_time(published_at)
    if not ts then return nil end
    local delta = (now or os.time()) - ts
    if delta < 0 then delta = 0 end
    if delta < 60 then return "now" end
    local minutes = math.floor(delta / 60)
    if minutes < 60 then return minutes .. "m" end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return hours .. "h" end
    return math.floor(hours / 24) .. "d"
end

local function fmt_relative(ts, now)
    if type(ts) ~= "number" then return nil end
    local delta = (now or os.time()) - ts
    if delta < 0 then delta = 0 end
    if delta < 60 then return "just now" end
    local minutes = math.floor(delta / 60)
    if minutes < 60 then return minutes .. " min ago" end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return hours .. " h ago" end
    return math.floor(hours / 24) .. " d ago"
end

local function hn_meta_line(item, now)
    local parts = {}
    if non_empty(item.domain) then table.insert(parts, item.domain) end
    if tonumber(item.score) then table.insert(parts, tostring(item.score) .. " pts") end
    if tonumber(item.descendants) then table.insert(parts, tostring(item.descendants) .. " comments") end
    if non_empty(item.by) then table.insert(parts, "by " .. item.by) end
    local age = fmt_age(item.published_at, now)
    if age then table.insert(parts, age) end
    if item.url == nil then table.insert(parts, "Ask HN") end
    if item.content_status and item.content_status ~= "ok" then
        table.insert(parts, "unavailable")
    end
    return table.concat(parts, " · ")
end

local function short_date(now)
    local ok, value = pcall(os.date, "%a, %d %b", now or os.time())
    if not ok or not value then return "" end
    return value:upper()
end

local function clock_with_meridiem(clock, use_24h)
    local hour, minute = tostring(clock or ""):match("^(%d+):(%d+)")
    if not (hour and minute) then return tostring(clock or "--:--"), nil end
    local h = tonumber(hour)
    if use_24h or not h then return tostring(clock), nil end
    local suffix = h < 12 and "AM" or "PM"
    local display = h % 12
    if display == 0 then display = 12 end
    return string.format("%d:%s", display, minute), suffix
end

function DashboardModel.build(state, opts)
    state = state or {}
    opts = opts or {}
    local now = opts.now or os.time()
    local page_size = tonumber(opts.page_size) or PAGE_SIZE

    local clock, meridiem = clock_with_meridiem(state.time, opts.clock_24h == true)
    local updated_clock = nil
    if type(state.refreshed_at) == "number" then
        local ok, value = pcall(os.date, "%H:%M", state.refreshed_at)
        if ok then updated_clock = value end
    end
    local battery = tostring(state.battery or "")
    local network = tostring(state.network or "")
    local charging = false
    if battery:find("charging", 1, true) and not battery:find("not charging", 1, true) then
        charging = true
    end
    local hero = {
        clock = clock,
        meridiem = meridiem,
        date_short = short_date(now),
        updated_clock = updated_clock,
        battery_pct = tonumber(battery:match("(%d+)%%")),
        charging = charging,
        wifi = network:find("connected", 1, true) and true or false,
        show_battery = state.show_battery ~= false,
        show_network = state.show_network ~= false,
    }

    local hint = non_empty(state.refresh_hint)

    local weather = nil
    if state.show_weather ~= false then
        local w = state.weather or {}
        local p = w.payload or {}
        weather = {
            icon = non_empty(p.icon) or "unknown",
            temp = fmt_temp(p.current_temp),
            condition = non_empty(p.condition_text),
            wind = fmt_int(p.wind_kmh) and (fmt_int(p.wind_kmh) .. " km/h") or nil,
            humidity = fmt_int(p.humidity) and (fmt_int(p.humidity) .. "%") or nil,
            hi = fmt_temp(p.temp_max),
            lo = fmt_temp(p.temp_min),
            place = non_empty(p.place_name),
            tomorrow = {
                icon = non_empty(p.tomorrow_icon) or "unknown",
                hi = fmt_temp(p.tomorrow_temp_max),
                lo = fmt_temp(p.tomorrow_temp_min),
            },
            fallback = (not fmt_temp(p.current_temp) and not non_empty(p.condition_text))
                and tostring(w.line or "Weather unavailable.") or nil,
            message = non_empty(w.message),
            stale = w.stale and true or false,
        }
    end

    local hn = nil
    if state.show_hn ~= false then
        local h = state.hn or {}
        local items = {}
        for index, item in ipairs(h.items or {}) do
            local id = item.id ~= nil and tostring(item.id) or nil
            if id == "" then id = nil end
            table.insert(items, {
                id = id,
                rank = tonumber(item.rank) or index,
                title = tostring(item.title or "(untitled)"),
                meta = hn_meta_line(item, now),
                unavailable = item.content_status ~= nil and item.content_status ~= "ok",
            })
        end
        local pages = math.ceil(#items / page_size)
        local page = tonumber(opts.page) or 1
        if page < 1 then page = 1 end
        if pages > 0 and page > pages then page = pages end
        local visible = {}
        local first = (page - 1) * page_size + 1
        local last = math.min(#items, first + page_size - 1)
        for i = first, last do visible[#visible + 1] = items[i] end
        hn = {
            badge = "Y/HN",
            title = "TOP STORIES",
            items = visible,
            page = pages > 0 and page or 1,
            pages = pages,
            page_size = page_size,
            empty = #items == 0 and tostring(h.line or "HN unavailable.") or nil,
            message = non_empty(h.message),
        }
    end

    local last_refreshed = nil
    if type(state.refreshed_at) == "number" then
        local relative = fmt_relative(state.refreshed_at, now)
        if relative then
            last_refreshed = {
                text = "Last refreshed: " .. relative,
                stale = state.refreshed_stale and true or false,
            }
        end
    end

    return {
        hero = hero,
        hint = hint,
        weather = weather,
        hn = hn,
        last_refreshed = last_refreshed,
        nav = { active = "dashboard", tabs = { "dashboard", "todos", "store" } },
        test_article = opts.test_article_ready == true,
    }
end

return DashboardModel
