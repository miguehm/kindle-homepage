local DashboardModel = {}

local function fmt_temp(value)
    if type(value) ~= "number" then return nil end
    return tostring(math.floor(value + 0.5)) .. "°C"
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
    local ok, date = pcall(os.date, "%Y-%m-%d", ts)
    if ok then return date end
    return nil
end

local function fmt_updated(fetched_at, stale, now)
    local rel = fmt_relative(fetched_at, now)
    if not rel then return nil end
    if stale then return "Updated " .. rel .. " · cached" end
    return "Updated " .. rel
end

local function non_empty(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

local function hn_meta_line(item)
    local parts = {}
    if tonumber(item.score) then table.insert(parts, tostring(item.score) .. " pts") end
    if tonumber(item.descendants) then table.insert(parts, tostring(item.descendants) .. " comments") end
    if non_empty(item.by) then table.insert(parts, "by " .. item.by) end
    if item.url == nil then table.insert(parts, "Ask HN") end
    if non_empty(item.domain) then table.insert(parts, item.domain) end
    if item.content_status and item.content_status ~= "ok" then
        table.insert(parts, "unavailable")
    end
    return table.concat(parts, " · ")
end

function DashboardModel.build(state, opts)
    state = state or {}
    opts = opts or {}
    local now = opts.now

    local hero = {
        clock = tostring(state.time or "--:--"),
        date = tostring(state.date or ""),
    }

    local status_parts = {}
    local battery = tostring(state.battery or "")
    local network = tostring(state.network or "")
    if battery ~= "" and battery ~= "Battery: hidden" then table.insert(status_parts, battery) end
    if network ~= "" and network ~= "Network: hidden" then table.insert(status_parts, network) end
    local status = #status_parts > 0 and table.concat(status_parts, "  ·  ") or nil

    local weather = nil
    if state.show_weather ~= false then
        local w = state.weather or {}
        local payload = w.payload or {}
        local temp = fmt_temp(payload.current_temp)
        local cond = non_empty(payload.condition_text)
        local detail = {}
        if non_empty(payload.place_name) then table.insert(detail, payload.place_name) end
        local hi = fmt_temp(payload.temp_max)
        local lo = fmt_temp(payload.temp_min)
        if hi or lo then
            table.insert(detail, "H:" .. (hi or "n/a") .. " L:" .. (lo or "n/a"))
        end
        weather = {
            title = "WEATHER",
            temp = temp,
            condition = cond,
            fallback = (not temp and not cond) and tostring(w.line or "Weather unavailable.") or nil,
            detail = #detail > 0 and table.concat(detail, " · ") or nil,
            updated = fmt_updated(w.fetched_at, w.stale, now),
            message = non_empty(w.message),
        }
    end

    local hn = nil
    if state.show_hn ~= false then
        local h = state.hn or {}
        local items = {}
        for index, item in ipairs(h.items or {}) do
            local raw_id = item.id
            local id = raw_id ~= nil and tostring(raw_id) or nil
            if id == "" then id = nil end
            table.insert(items, {
                id = id,
                rank = tonumber(item.rank) or index,
                title = tostring(item.title or "(untitled)"),
                meta = hn_meta_line(item),
            })
        end
        hn = {
            title = "HACKER NEWS",
            items = items,
            empty = #items == 0 and tostring(h.line or "HN unavailable.") or nil,
            message = non_empty(h.message),
            updated = fmt_updated(h.fetched_at, h.stale, now),
        }
    end

    local hint = non_empty(state.refresh_hint)

    return {
        hero = hero,
        status = status,
        hint = hint,
        weather = weather,
        hn = hn,
        test_article = opts.test_article_ready == true,
        footer = "Tap a headline to read it. Actions are below.",
    }
end

return DashboardModel
