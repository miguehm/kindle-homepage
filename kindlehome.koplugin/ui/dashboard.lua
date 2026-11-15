local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local _ = require("gettext")

local Logger = require("lib/logger")
local MdToHtml = require("lib/render/md_to_html")
local ArticleStore = require("lib/article_store")
local Refresh = require("lib/refresh")
local WeatherState = require("lib/weather_state")

local Dashboard = {}

function Dashboard:new(opts)
    opts = opts or {}
    local o = {
        config = opts.config,
        paths = opts.paths,
        actions = opts.actions,
        article_view = opts.article_view,
        widget = nil,
        article_store = opts.paths and ArticleStore:new(opts.paths) or nil,
        last_test_doc = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

local function escape_html(s)
    return MdToHtml.escape(s)
end

local function get_clock_state()
    local ok_time, t = pcall(os.date, "*t")
    local ok_str, date_str = pcall(os.date, "%A, %B %d, %Y")
    local ok_hm, time_str = pcall(os.date, "%H:%M")
    if not (ok_time and t and ok_str and ok_hm) then
        return "Date unavailable", "Time unavailable"
    end
    return date_str, time_str
end

local function get_battery_state(config)
    if config and not config:get("show_battery") then
        return "Battery: hidden"
    end
    local ok, powerd = pcall(function() return Device:getPowerDevice() end)
    if not ok or not powerd then
        return "Battery: unavailable"
    end
    local parts = {}
    local ok_cap, cap = pcall(function() return powerd:getCapacity() end)
    if ok_cap and cap ~= nil then
        table.insert(parts, tostring(cap) .. "%")
    end
    local charging = nil
    if type(powerd.isCharging) == "function" then
        local ok_c, c = pcall(function() return powerd:isCharging() end)
        if ok_c then charging = c end
    elseif type(powerd.is_charging) == "function" then
        local ok_c, c = pcall(function() return powerd:is_charging() end)
        if ok_c then charging = c end
    end
    if charging == true then
        table.insert(parts, "charging")
    elseif charging == false and #parts > 0 then
        table.insert(parts, "not charging")
    end
    if #parts == 0 then
        return "Battery: unavailable"
    end
    return "Battery: " .. table.concat(parts, ", ")
end

local function get_network_state(config)
    if config and not config:get("show_network") then
        return "Network: hidden"
    end
    local connected = false
    local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
    if ok_conn then
        connected = conn and true or false
    end
    if not connected then
        return "Network: disconnected"
    end
    local ssid = nil
    local ok_info, info = pcall(function()
        if type(NetworkMgr.getNetworkInfo) == "function" then
            return NetworkMgr:getNetworkInfo()
        end
        if type(NetworkMgr.getCurrentNetwork) == "function" then
            return NetworkMgr:getCurrentNetwork()
        end
        return nil
    end)
    if ok_info and type(info) == "table" then
        ssid = info.ssid or info.SSID
    end
    if type(ssid) == "string" and ssid ~= "" then
        return "Network: connected (" .. ssid .. ")"
    end
    return "Network: connected"
end

function Dashboard:load_weather(opts)
    opts = opts or {}
    local allow_network = opts.allow_network
    if allow_network == nil then
        local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
        allow_network = ok_conn and conn and true or false
    end
    local budget = Refresh.new_budget(self.config and self.config:get("refresh_budget_s") or 20)
    local ok, res = pcall(WeatherState.load, self.config, self.paths, {
        allow_network = allow_network,
        budget = budget,
    })
    if not ok then
        Logger.err("dashboard", "weather_load_exception", { err = tostring(res) })
        return { status = "error", line = "Weather: unavailable." }
    end
    return res
end

function Dashboard:build_state(opts)
    local date_str, time_str = get_clock_state()
    local weather = self:load_weather(opts or {})
    local state = {
        date = date_str,
        time = time_str,
        battery = get_battery_state(self.config),
        network = get_network_state(self.config),
        weather = weather,
    }
    Logger.info("dashboard", "state_built", {
        has_time = state.time ~= "Time unavailable",
        battery = state.battery,
        network = state.network,
        weather = weather and weather.status or "nil",
    })
    return state
end

local function fmt_epoch(ts)
    if type(ts) ~= "number" then return nil end
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", ts)
    if ok then return s end
    return nil
end

local function build_html(state)
    local links = {}
    if state.test_article_ready then
        table.insert(links, "<div class='label'>Test article saved (Phase 3). Use action button to open.</div>")
    end
    local weather = state.weather or { status = "error", line = "Weather: unavailable." }
    local weather_meta = ""
    if weather.fetched_at then
        local ts = fmt_epoch(weather.fetched_at)
        if ts then
            weather_meta = "Last update: " .. escape_html(ts)
            if weather.stale then weather_meta = weather_meta .. " (cached)" end
        end
    end
    local weather_note = ""
    if weather.status == "configure_location" then
        weather_note = "Set location in Kindle Home settings (search place or enter lat/lon)."
    elseif weather.status == "error" and (weather.error_kind == "offline" or weather.error_kind == "timeout" or weather.error_kind == "network") then
        weather_note = "Turn on WiFi and refresh to update weather."
    elseif weather.status == "stale" then
        weather_note = "Showing cached weather."
    end

    return table.concat({
        "<html><head><style>",
        "body{font-family:sans-serif;margin:24px;color:#111;background:#fff;}",
        "h1{font-size:30px;margin:0 0 8px 0;}",
        "h2{font-size:22px;margin:0 0 18px 0;font-weight:normal;}",
        ".section{margin:18px 0;padding-top:12px;border-top:1px solid #333;}",
        ".label{font-size:18px;margin:6px 0;}",
        ".muted{font-size:16px;color:#444;margin-top:10px;}",
        "</style></head><body>",
        "<h1>Kindle Home</h1>",
        "<h2>", escape_html(state.date), "</h2>",
        "<div class='label'><b>Time:</b> ", escape_html(state.time), "</div>",
        "<div class='section'>",
        "<div class='label'>", escape_html(state.battery), "</div>",
        "<div class='label'>", escape_html(state.network), "</div>",
        "</div>",
        "<div class='section'>",
        "<div class='label'><b>Weather</b></div>",
        "<div class='label'>", escape_html(weather.line or "Weather: unavailable."), "</div>",
        weather_meta ~= "" and ("<div class='muted'>" .. weather_meta .. "</div>") or "",
        weather_note ~= "" and ("<div class='muted'>" .. escape_html(weather_note) .. "</div>") or "",
        "</div>",
        "<div class='section'>",
        "<div class='label'><b>Reading:</b> renderer, article overlay and persistence scaffold (Phase 3).</div>",
        table.concat(links),
        "</div>",
        "<p class='muted'>Refresh updates local status and weather (cache-first). Scroll position may reset on refresh. Navigation uses internal actions (Lua), not HTML taps.</p>",
        "</body></html>",
    })
end

function Dashboard:ensure_test_article()
    if self.last_test_doc and self.last_test_doc.md_path then
        return self.last_test_doc
    end
    if not (self.paths and self.paths.ensure_base_dirs and self.paths.ensure_dir) then
        Logger.warn("dashboard", "test_article_no_paths")
        return nil, "paths_unavailable"
    end
    self.paths:ensure_base_dirs()
    self.paths:ensure_dir(self.paths:articles_hn_dir())
    if not self.article_store then
        self.article_store = ArticleStore:new(self.paths)
    end
    local meta = {
        id = "test-phase3",
        title = "KindleHome Phase 3 Test Article",
        source = "kindlehome:test",
        date = os.date("%Y-%m-%d"),
        status = "ok",
    }
    local md = table.concat({
        "# Phase 3 Reading Test",
        "",
        "This article verifies MD to HTML rendering, persistence (.md/.html), and overlay navigation.",
        "",
        "## Formatting",
        "",
        "- Bullet item",
        "- **Bold** and *italic* and `inline code`",
        "1. Ordered item",
        "",
        "A [safe link](https://example.com) and an unsafe javascript: link should be rendered safely.",
        "",
        "```",
        "preformatted code block",
        "line 2",
        "```",
        "",
        "---",
        "",
        "Escaping check: <script>alert('x')</script> & <b>tag</b>.",
    }, "\n")
    local saved, err = self.article_store:save({ kind = "hn", meta = meta, md = md })
    if not saved then
        Logger.err("dashboard", "test_article_save_failed", { err = err })
        return nil, err
    end
    self.last_test_doc = {
        kind = "hn",
        id = meta.id,
        title = meta.title,
        meta = meta,
        md = md,
        html = saved.html,
        html_path = saved.html_path,
        md_path = saved.md_path,
        on_back = function() self:show() end,
    }
    Logger.info("dashboard", "test_article_saved", { md = saved.md_path, html = saved.html_path })
    return self.last_test_doc
end

function Dashboard:open_test_article()
    local doc, err = self:ensure_test_article()
    if not doc then
        if self.article_view then
            self.article_view:show({ status = "content_unavailable", title = "Reading", meta = { status = tostring(err or "unavailable") } })
        end
        return
    end
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
    if self.article_view then
        self.article_view:show(doc)
    else
        Logger.warn("dashboard", "no_article_view")
    end
end

function Dashboard:show(opts)
    opts = opts or {}
    -- Single refresh contract: rebuild local state/HTML and (re)open widget in a controlled way.
    -- Note: replacing the widget resets scroll position (accepted in Phase 1).
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    local state = self:build_state(opts)
    state.test_article_ready = self.last_test_doc ~= nil
    local html = build_html(state)
    self.widget = ScrollHtmlWidget:new{
        html_body = html,
        css = "",
        default_font_size = Screen:scaleBySize(20),
        title = _("Kindle Home"),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        actions = {
            {
                text = _("Refresh"),
                callback = function()
                    if self.actions then self.actions:dispatch("refresh", { source = "dashboard", dashboard = self, user_initiated = true }) else self:refresh(opts) end
                end,
            },
            {
                text = _("Open test article"),
                callback = function()
                    if self.actions then self.actions:dispatch("open_hn", { source = "dashboard", dashboard = self }, "open_hn:test-phase3", "test-phase3")
                    else self:open_test_article() end
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    if self.actions then self.actions:dispatch("close", { source = "dashboard", dashboard = self }) else self:close() end
                end,
            },
        },
    }
    UIManager:show(self.widget)
    Logger.info("dashboard", "shown", { weather = state.weather and state.weather.status })
end

function Dashboard:refresh(opts)
    Logger.info("dashboard", "refresh", { allow_network = opts and opts.allow_network })
    self:show(opts)
end

function Dashboard:close()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
    Logger.info("dashboard", "closed")
end

return Dashboard
