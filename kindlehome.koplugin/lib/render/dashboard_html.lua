-- Dashboard HTML fragment (no <html>/<head>): ScrollHtmlWidget wraps it and
-- takes its stylesheet through the `css` option.
--
-- This module is intentionally free of KOReader/widget dependencies so the
-- offline smoke test can validate the markup on plain Lua 5.1.

local MdToHtml = require("lib/render/md_to_html")

local DashboardHtml = {}

local function escape_html(s)
    return MdToHtml.escape(s)
end

local function safe_href_id(id)
    return tostring(id or ""):gsub("[^%w%-_%.]", "")
end

local function fmt_temp(value)
    if type(value) ~= "number" then return nil end
    return tostring(math.floor(value + 0.5)) .. "°C"
end

local function fmt_relative(ts)
    if type(ts) ~= "number" then return nil end
    local delta = os.time() - ts
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

local function add_updated(parts, fetched_at, stale)
    local rel = fmt_relative(fetched_at)
    if not rel then return end
    local text = "Updated " .. rel
    if stale then text = text .. " · cached" end
    table.insert(parts, "<div class='muted'>" .. escape_html(text) .. "</div>")
end

local function build_hero(state, out)
    table.insert(out, "<div class='hero'>")
    table.insert(out, "<div class='clock'>" .. escape_html(state.time or "--:--") .. "</div>")
    table.insert(out, "<div class='date'>" .. escape_html(state.date or "") .. "</div>")
    table.insert(out, "</div>")
end

local function build_status(state, out)
    local parts = {}
    local battery = tostring(state.battery or "")
    local network = tostring(state.network or "")
    if battery ~= "" and battery ~= "Battery: hidden" then table.insert(parts, battery) end
    if network ~= "" and network ~= "Network: hidden" then table.insert(parts, network) end
    if #parts == 0 then return end
    table.insert(out, "<div class='status'>" .. escape_html(table.concat(parts, "  ·  ")) .. "</div>")
end

local function build_weather(state, out)
    local weather = state.weather or { status = "error", line = "Weather unavailable." }
    table.insert(out, "<div class='card'>")
    table.insert(out, "<div class='card-title'>WEATHER</div>")

    local payload = weather.payload or {}
    local temp = fmt_temp(payload.current_temp)
    local cond = payload.condition_text
    local place = payload.place_name
    local hi = fmt_temp(payload.temp_max)
    local lo = fmt_temp(payload.temp_min)

    if temp then
        table.insert(out, "<div class='temp'>" .. escape_html(temp) .. "</div>")
    end
    if cond and cond ~= "" then
        table.insert(out, "<div class='cond'>" .. escape_html(cond) .. "</div>")
    elseif not temp then
        table.insert(out, "<div class='cond'>" .. escape_html(weather.line or "Weather unavailable.") .. "</div>")
    end

    local detail = {}
    if place and place ~= "" then table.insert(detail, escape_html(place)) end
    if hi or lo then
        table.insert(detail, "H:" .. (hi and escape_html(hi) or "n/a") .. " L:" .. (lo and escape_html(lo) or "n/a"))
    end
    if #detail > 0 then
        table.insert(out, "<div class='small'>" .. table.concat(detail, " · ") .. "</div>")
    end

    add_updated(out, weather.fetched_at, weather.stale)
    if weather.message and weather.message ~= "" then
        table.insert(out, "<div class='muted'>" .. escape_html(weather.message) .. "</div>")
    end
    table.insert(out, "</div>")
end

local function hn_meta_line(item)
    local parts = {}
    if tonumber(item.score) then table.insert(parts, tostring(item.score) .. " pts") end
    if tonumber(item.descendants) then table.insert(parts, tostring(item.descendants) .. " comments") end
    if item.by and item.by ~= "" then table.insert(parts, "by " .. escape_html(item.by)) end
    if item.url == nil then table.insert(parts, "Ask HN") end
    if item.domain and item.domain ~= "" then table.insert(parts, escape_html(item.domain)) end
    if item.content_status and item.content_status ~= "ok" then
        table.insert(parts, "unavailable")
    end
    return table.concat(parts, " · ")
end

local function build_hn(state, out)
    local hn = state.hn or { status = "error", line = "HN unavailable.", items = {} }
    local items = hn.items or {}
    table.insert(out, "<div class='card'>")
    table.insert(out, "<div class='card-title'>HACKER NEWS</div>")
    if #items == 0 then
        table.insert(out, "<div class='cond'>" .. escape_html(hn.line or "HN unavailable.") .. "</div>")
    else
        for index, item in ipairs(items) do
            local id = safe_href_id(item.id)
            local rank = tonumber(item.rank) or index
            local title = tostring(item.title or "(untitled)")
            local row_class = index == 1 and "hn hn-first" or "hn"
            table.insert(out, "<div class='" .. row_class .. "'>")
            if id ~= "" then
                table.insert(out, string.format(
                    "<div class='hn-title'><a href='kh:hn:%s'><span class='rank'>%d.</span> %s</a></div>",
                    id, rank, escape_html(title)))
            else
                table.insert(out, string.format(
                    "<div class='hn-title'><span class='rank'>%d.</span> %s</div>", rank, escape_html(title)))
            end
            local meta = hn_meta_line(item)
            if meta ~= "" then
                table.insert(out, "<div class='hn-meta'>" .. meta .. "</div>")
            end
            table.insert(out, "</div>")
        end
    end
    if hn.message and hn.message ~= "" then
        table.insert(out, "<div class='muted'>" .. escape_html(hn.message) .. "</div>")
    end
    add_updated(out, hn.fetched_at, hn.stale)
    table.insert(out, "</div>")
end

local function build_digest(state, out)
    local digest = state.digest_latest
    table.insert(out, "<div class='card'>")
    table.insert(out, "<div class='card-title'>DIGEST</div>")
    if digest and digest.date then
        table.insert(out, "<div class='cond'>Available: " .. escape_html(tostring(digest.date)) .. "</div>")
        table.insert(out, "<div class='small'><a href='kh:digest:latest'>Open latest digest</a></div>")
    else
        table.insert(out, "<div class='cond'>Not generated yet.</div>")
        table.insert(out, "<div class='muted'>Use the Digest button below to create today's summary.</div>")
    end
    table.insert(out, "</div>")
end

function DashboardHtml.build(state, opts)
    state = state or {}
    opts = opts or {}
    local out = {}
    build_hero(state, out)
    build_status(state, out)

    if state.refresh_hint and state.refresh_hint ~= "" then
        table.insert(out, "<div class='hint'>" .. escape_html(tostring(state.refresh_hint)) .. "</div>")
    end

    if state.show_weather ~= false then build_weather(state, out) end
    if state.show_hn ~= false then build_hn(state, out) end
    if state.show_digest ~= false then build_digest(state, out) end

    if opts.test_article_ready then
        table.insert(out, "<div class='card'><div class='card-title'>DEVELOPMENT</div>")
        table.insert(out, "<div class='small'><a href='kh:test'>Open test article</a></div></div>")
    end

    table.insert(out, "<div class='footer-note'>Tap a headline to read it. Use the buttons below to refresh, create a digest, or exit.</div>")
    return table.concat(out)
end

return DashboardHtml
