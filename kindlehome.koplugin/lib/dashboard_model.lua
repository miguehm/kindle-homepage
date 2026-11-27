-- SPDX-License-Identifier: MIT
local DashboardModel = {}

local PAGE_SIZE = 4
local DUE_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"
local DEFAULT_DUE_DAYS = 3

-- Deadlines are canonical YYYY-MM-DD strings; comparing them lexicographically
-- is the same as comparing calendar dates. With todos_timezone configured the
-- device clock is expected to match that zone, so use the local day; otherwise
-- both the plugin and the server use UTC.
local function due_bounds(now, due_days, use_local)
    now = tonumber(now) or os.time()
    due_days = tonumber(due_days) or DEFAULT_DUE_DAYS
    if due_days < 1 then due_days = 1 end
    if due_days > 30 then due_days = 30 end
    local fmt = use_local and "%Y-%m-%d" or "!%Y-%m-%d"
    return os.date(fmt, now), os.date(fmt, now + due_days * 86400)
end

local function classify_due(due, today, limit)
    if type(due) ~= "string" or due == "" then return nil end
    if due < today then return "overdue" end
    if due <= limit then return "due_soon" end
    return nil
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- "27 Nov 2026" (no locale dependency: os.date month names follow the C
-- locale on device, which may not be English).
local function format_due(due)
    if type(due) ~= "string" then return nil end
    local y, m, d = due:match(DUE_PATTERN)
    if not y then return due end
    local month = MONTHS[tonumber(m)]
    if not month then return due end
    return tostring(tonumber(d)) .. " " .. month .. " " .. y
end

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

local function redundant_notice(message, hint)
    if not hint or not message then return false end
    if message == hint then return true end
    return message:find("Offline", 1, true) ~= nil
        or message:find("Network timeout", 1, true) ~= nil
        or message:find("Network error", 1, true) ~= nil
        or message:find("cached", 1, true) ~= nil
        or message:find("Refresh issue", 1, true) ~= nil
        or message:find("Refresh budget exceeded", 1, true) ~= nil
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

-- One compact line: domain · points · comments · age, plus availability.
-- The author is left out to keep the line short enough for a single row.
local function hn_meta_line(item, now)
    local parts = {}
    if non_empty(item.domain) then table.insert(parts, item.domain) end
    if tonumber(item.score) then table.insert(parts, tostring(item.score) .. " pts") end
    if tonumber(item.descendants) then table.insert(parts, tostring(item.descendants) .. " comments") end
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

local function fmt_clock(ts, use_24h)
    if type(ts) ~= "number" then return nil end
    local ok, value = pcall(os.date, "%H:%M", ts)
    if not ok or not value then return nil end
    local clock, meridiem = clock_with_meridiem(value, use_24h)
    return meridiem and (clock .. " " .. meridiem) or clock
end

-- Absolute refresh time ("Updated 10:40"). Unlike "5 min ago" it does not
-- change every minute, so the stories card is not repainted on clock ticks.
local function freshness_label(state, use_24h)
    local clock = fmt_clock(state.refreshed_at, use_24h)
    if not clock then return nil end
    return (state.refreshed_stale and "Cached " or "Updated ") .. clock
end

local function build_shared(state, now, opts)
    local clock, meridiem = clock_with_meridiem(state.time, opts.clock_24h == true)
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
        battery_pct = tonumber(battery:match("(%d+)%%")),
        charging = charging,
        wifi = network:find("connected", 1, true) and true or false,
        refreshing = state.refreshing == true,
        show_battery = state.show_battery ~= false,
        show_network = state.show_network ~= false,
    }
    return hero, non_empty(state.refresh_hint)
end

function DashboardModel.build(state, opts)
    state = state or {}
    opts = opts or {}
    local now = opts.now or os.time()
    local page_size = tonumber(opts.page_size) or PAGE_SIZE

    local hero, hint = build_shared(state, now, opts)
    -- The Top Stories header carries the refresh indicator; the hero shows it
    -- only when that card is hidden. Keeping the flag off otherwise means a
    -- refresh toggle does not repaint the hero.
    hero.refreshing = hero.refreshing and state.show_hn == false

    local weather = nil
    if state.show_weather ~= false then
        local w = state.weather or {}
        local p = w.payload or {}
        local weather_message = non_empty(w.message)
        if redundant_notice(weather_message, hint) then weather_message = nil end
        local weather_fallback = (not fmt_temp(p.current_temp) and not non_empty(p.condition_text))
            and tostring(w.line or "Weather unavailable.") or nil
        if redundant_notice(weather_fallback, hint) then weather_fallback = nil end
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
            fallback = weather_fallback,
            message = weather_message,
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
            local meta = hn_meta_line(item, now)
            if item.saved then meta = meta .. (meta ~= "" and " · " or "") .. "Saved" end
            table.insert(items, {
                id = id,
                rank = tonumber(item.rank) or index,
                title = tostring(item.title or "(untitled)"),
                meta = meta,
                saved = item.saved == true,
                unavailable = item.content_status ~= nil and item.content_status ~= "ok",
            })
        end
        local refreshed = freshness_label(state, opts.clock_24h == true)
        local hn_message = non_empty(h.message)
        if redundant_notice(hn_message, hint) then hn_message = nil end
        local pages = math.ceil(#items / page_size)
        local page = tonumber(opts.page) or 1
        if page < 1 then page = 1 end
        if pages > 0 and page > pages then page = pages end
        local visible = {}
        if opts.worst_case then
            -- Layout probe: the rows with the longest titles, so the row
            -- count measured on them fits every page of the feed.
            local sorted = {}
            for i, item in ipairs(items) do sorted[i] = item end
            table.sort(sorted, function(a, b)
                if #a.title ~= #b.title then return #a.title > #b.title end
                return #a.meta > #b.meta
            end)
            for i = 1, math.min(page_size, #sorted) do visible[i] = sorted[i] end
        else
            local first = (page - 1) * page_size + 1
            local last = math.min(#items, first + page_size - 1)
            for i = first, last do visible[#visible + 1] = items[i] end
        end
        local empty, empty_kind = nil, nil
        if #items == 0 then
            -- Nothing cached and no fetch attempted yet (cache-first open
            -- while offline): say so instead of claiming HN is down.
            if type(h.fetched_at) ~= "number" and not h.error_kind then
                empty, empty_kind = "Not loaded yet. Tap refresh to load stories.", "not_loaded"
            else
                empty, empty_kind = tostring(h.line or "HN unavailable."), "error"
            end
        end
        hn = {
            badge = "Y/HN",
            title = "TOP STORIES",
            items = visible,
            page = pages > 0 and page or 1,
            pages = pages,
            page_size = page_size,
            empty = empty,
            empty_kind = empty_kind,
            message = hn_message,
            refreshed = refreshed,
            refreshing = state.refreshing == true,
            longest_title = (function()
                local n = 0
                for _, item in ipairs(items) do if #item.title > n then n = #item.title end end
                return n
            end)(),
            total = #items,
        }
    end

    return {
        hero = hero,
        hint = hint,
        weather = weather,
        hn = hn,
        nav = { active = "dashboard", tabs = { "dashboard", "todos", "store" } },
    }
end

local function clamp_page(page, pages)
    page = math.floor(tonumber(page) or 1)
    if page < 1 then page = 1 end
    if pages > 0 and page > pages then page = pages end
    return page
end

local UNTAGGED_FILTER = "__untagged__"

local function detail_preview(details)
    details = tostring(details or "")
    if details == "" then return nil end
    details = details:gsub("%s+", " ")
    if #details > 120 then
        return details:sub(1, 119) .. "…"
    end
    return details
end

local function matches_tag(task, filter)
    if not filter or filter == "" then return true end
    local tags = task.tags or {}
    if filter == UNTAGGED_FILTER then return #tags == 0 end
    for _, tag in ipairs(tags) do
        if tostring(tag) == filter then return true end
    end
    return false
end

local function matches_status(task, status, today, limit)
    if status == "open" then return task.done ~= true end
    if status == "done" then return task.done == true end
    if status == "due_soon" or status == "overdue" then
        if task.done then return false end
        return classify_due(task.due_date, today, limit) == status
    end
    return true
end

local function status_count(counts, status)
    counts = counts or {}
    if status == "open" then return tonumber(counts.open) or 0 end
    if status == "done" then return tonumber(counts.done) or 0 end
    if status == "due_soon" then return tonumber(counts.due_soon) or 0 end
    if status == "overdue" then return tonumber(counts.overdue) or 0 end
    return tonumber(counts.total) or 0
end

local function status_word(status)
    if status == "open" then return "open tasks" end
    if status == "done" then return "done tasks" end
    if status == "due_soon" then return "tasks due soon" end
    if status == "overdue" then return "overdue tasks" end
    return "tasks"
end

function DashboardModel.build_todos(state, opts)
    state = state or {}
    opts = opts or {}
    local now = opts.now or os.time()
    local hero, hint = build_shared(state, now, opts)

    local todos_state = state.todos or {}
    local payload = todos_state.payload or {}
    local counts = payload.counts or {}
    local filter = opts.tag_filter or ""
    if filter == "all" then filter = "" end
    local status_filter = opts.status_filter or "all"
    if status_filter ~= "open" and status_filter ~= "done" and status_filter ~= "all"
            and status_filter ~= "due_soon" and status_filter ~= "overdue" then
        status_filter = "all"
    end
    local today, limit = due_bounds(now, opts.due_days, opts.use_local)

    local untagged = { open = 0, done = 0, total = 0, due_soon = 0, overdue = 0 }
    for _, task in ipairs(payload.items or {}) do
        if #(task.tags or {}) == 0 then
            untagged.total = untagged.total + 1
            local class = (not task.done) and classify_due(task.due_date, today, limit) or nil
            if task.done then untagged.done = untagged.done + 1 else untagged.open = untagged.open + 1 end
            if class == "due_soon" then untagged.due_soon = untagged.due_soon + 1
            elseif class == "overdue" then untagged.overdue = untagged.overdue + 1 end
        end
    end

    local function task_row(task)
        local parts = {}
        local tag_parts = {}
        for _, tag in ipairs(task.tags or {}) do
            table.insert(tag_parts, "#" .. tostring(tag))
        end
        if #tag_parts > 0 then table.insert(parts, table.concat(tag_parts, " ")) end
        local due_label = format_due(task.due_date)
        if due_label then
            local class = (not task.done) and classify_due(task.due_date, today, limit) or nil
            table.insert(parts, (class == "overdue" and "Overdue " or "Due ") .. due_label)
        end
        local details = tostring(task.details or "")
        return {
            id = tostring(task.id),
            title = tostring(task.title or ""),
            done = task.done == true,
            due_date = task.due_date,
            meta = #parts > 0 and table.concat(parts, " · ") or "—",
            details = details,
            detail_preview = detail_preview(details),
            has_details = details ~= "",
        }
    end

    local tasks = {}
    for _, task in ipairs(payload.items or {}) do
        if matches_tag(task, filter) and matches_status(task, status_filter, today, limit) then
            table.insert(tasks, task_row(task))
        end
    end

    local status_chips = {
        { kind = "status", value = "open", label = "Open",
          count = status_count(counts, "open"), active = status_filter == "open" },
        { kind = "status", value = "done", label = "Done",
          count = status_count(counts, "done"), active = status_filter == "done" },
        { kind = "status", value = "all", label = "All",
          count = status_count(counts, "total"), active = status_filter == "all" },
        { kind = "status", value = "due_soon", label = "Due soon",
          count = status_count(counts, "due_soon"), active = status_filter == "due_soon" },
        { kind = "status", value = "overdue", label = "Overdue",
          count = status_count(counts, "overdue"), active = status_filter == "overdue" },
    }

    local chips = {}
    if opts.show_tags ~= false then
        table.insert(chips, {
            tag = "all", label = "No filter", count = status_count(counts, status_filter),
            active = filter == "", can_open = false,
        })
        for _, entry in ipairs(payload.tags or {}) do
            local tag = tostring(entry.tag or "")
            if tag ~= "" and (tonumber(entry.total) or 0) > 0 then
                local count = status_count(entry, status_filter)
                table.insert(chips, {
                    tag = tag, label = "#" .. tag, count = count,
                    active = filter == tag, can_open = count > 0,
                })
            end
        end
        local untagged_count = status_count(untagged, status_filter)
        if untagged_count > 0 then
            table.insert(chips, {
                tag = UNTAGGED_FILTER, label = "Untagged", count = untagged_count,
                active = filter == UNTAGGED_FILTER, can_open = false,
            })
        end
    end

    local page_size = math.floor(tonumber(opts.task_rows) or 6)
    if page_size < 1 then page_size = 1 end
    if page_size > 10 then page_size = 10 end
    local pages = math.ceil(#tasks / page_size)
    local page = clamp_page(opts.todos_page, pages)
    local visible = {}
    local longest = 0
    local all_rows = {}
    for _, task in ipairs(payload.items or {}) do
        local row = task_row(task)
        all_rows[#all_rows + 1] = row
        local weight = #row.title + #(row.detail_preview or "")
        if weight > longest then longest = weight end
    end
    if opts.worst_case then
        -- Layout probe over every task (not only the filtered ones), so the
        -- row count fits every page under every filter.
        table.sort(all_rows, function(a, b)
            local wa = #a.title + #(a.detail_preview or "")
            local wb = #b.title + #(b.detail_preview or "")
            if wa ~= wb then return wa > wb end
            return #a.meta > #b.meta
        end)
        for i = 1, math.min(page_size, #all_rows) do visible[i] = all_rows[i] end
    else
        local first = (page - 1) * page_size + 1
        local last = math.min(#tasks, first + page_size - 1)
        for i = first, last do visible[#visible + 1] = tasks[i] end
    end

    local todos_message = non_empty(todos_state.message)
    if redundant_notice(todos_message, hint) then todos_message = nil end
    local empty = nil
    if #tasks == 0 then
        local line = tostring(todos_state.line or "")
        if filter == "" and #(payload.items or {}) == 0 and line:find("unavailable", 1, true) then
            empty = line
        elseif filter == UNTAGGED_FILTER then
            empty = "No untagged " .. status_word(status_filter) .. "."
        elseif filter ~= "" then
            empty = "No " .. status_word(status_filter) .. " tagged #" .. filter .. "."
        else
            empty = "No " .. status_word(status_filter) .. "."
        end
    end
    -- Compact date + time line for the TASKS card header. The dashboard keeps
    -- its large hero clock; the TODO'S view gets the same information in small
    -- muted type. No timer: it is rebuilt whenever the view is repainted.
    local clock_line = hero.date_short or ""
    if hero.clock and hero.clock ~= "" then
        clock_line = clock_line .. (clock_line ~= "" and " · " or "") .. hero.clock
        if hero.meridiem then clock_line = clock_line .. " " .. hero.meridiem end
    end

    local todos_model = {
        badge = "TODO",
        title = "TASKS",
        clock_line = clock_line,
        items = visible,
        page = pages > 0 and page or 1,
        pages = pages,
        page_size = page_size,
        empty = empty,
        message = todos_message,
        counts = { open = counts.open or 0, done = counts.done or 0,
                   due_soon = counts.due_soon or 0, overdue = counts.overdue or 0 },
        truncated = payload.truncated and true or false,
        partial = payload.partial and true or false,
        visible_count = #tasks,
        refreshing = hero.refreshing == true,
        total = #all_rows,
        longest = longest,
        tags = chips,
        status_chips = status_chips,
        active_tag = filter,
        active_status = status_filter,
    }

    return {
        hero = hero,
        hint = hint,
        todos = todos_model,
        nav = { active = "todos", tabs = { "dashboard", "todos", "store" } },
    }
end

return DashboardModel
