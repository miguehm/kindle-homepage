local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Logger = require("lib/logger")
local MdToHtml = require("lib/render/md_to_html")
local ArticleStore = require("lib/article_store")
local Refresh = require("lib/refresh")
local WeatherState = require("lib/weather_state")
local HnmdState = require("lib/hnmd_state")
local Digest = require("lib/digest")
local Messages = require("ui/messages")

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
        hn_state = nil,
        hn_items = {},
        hn_item_index = {},
        last_state = nil,
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
    if self.config and not self.config:get("show_weather") then
        return { status = "hidden", line = "Weather: hidden", items = nil }
    end
    local allow_network = opts.allow_network
    if allow_network == nil then
        local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
        allow_network = ok_conn and conn and true or false
    end
    local budget = opts.budget or Refresh.new_budget(self.config and self.config:get("refresh_budget_s") or 20)
    local ok, res = pcall(WeatherState.load, self.config, self.paths, {
        allow_network = allow_network,
        budget = budget,
    })
    if not ok then
        Logger.err("dashboard", "weather_load_exception")
        return { status = "error", line = "Weather unavailable.", error_kind = "exception" }
    end
    if res and res.status ~= "hidden" and res.status ~= "disabled" then
        local msg = Messages.weather(res.error_kind, res.status)
        if msg then res.message = msg end
    end
    return res
end

function Dashboard:load_hn(opts)
    opts = opts or {}
    if self.config and not self.config:get("show_hn") then
        self.hn_state = { status = "hidden", line = "HN: hidden", items = {} }
        self.hn_items, self.hn_item_index = {}, {}
        return self.hn_state
    end
    local allow_network = opts.allow_network
    if allow_network == nil then
        local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
        allow_network = ok_conn and conn and true or false
    end
    local budget = opts.budget or Refresh.new_budget(self.config and self.config:get("refresh_budget_s") or 20)
    local ok, res = pcall(HnmdState.load, self.config, self.paths, {
        allow_network = allow_network,
        budget = budget,
    })
    if not ok then
        Logger.err("dashboard", "hn_load_exception")
        res = { status = "error", line = "HN unavailable.", items = {}, error_kind = "exception" }
    end
    self.hn_state = res
    self.hn_items = (res and type(res.items) == "table") and res.items or {}
    local max_items = tonumber(self.config and self.config:get("hnmd_max_items")) or 10
    if #self.hn_items > max_items then
        local trimmed = {}
        for i = 1, max_items do trimmed[i] = self.hn_items[i] end
        self.hn_items = trimmed
        if res then res.items = trimmed end
    end
    self.hn_item_index = {}
    for _, item in ipairs(self.hn_items) do
        if item and item.id ~= nil then
            self.hn_item_index[tostring(item.id)] = item
        end
    end
    if res and res.status ~= "hidden" and res.status ~= "disabled" then
        local msg = Messages.hn(res.error_kind, res.status, #self.hn_items > 0)
        if msg then res.message = msg; if res.status == "error" or res.status == "stale" then res.line = msg end end
    end
    return res
end

function Dashboard:get_hn_item(id)
    if id == nil then return nil end
    return self.hn_item_index and self.hn_item_index[tostring(id)] or nil
end

function Dashboard:build_state(opts)
    opts = opts or {}
    local date_str, time_str = get_clock_state()
    local budget = opts.budget or Refresh.new_budget(self.config and self.config:get("refresh_budget_s") or 20)
    local weather = self:load_weather({ allow_network = opts.allow_network, budget = budget })
    local hn = self:load_hn({ allow_network = opts.allow_network, budget = budget })
    local ok_date, date_iso = pcall(os.date, "%Y-%m-%d")
    local digest_latest = nil
    local show_digest = (not self.config) or self.config:get("show_digest")
    if show_digest and self.paths then
        local ok_d, p = pcall(Digest.latest, self.paths)
        if ok_d and p then digest_latest = p end
    end
    local state = {
        date = date_str,
        time = time_str,
        date_iso = ok_date and date_iso or nil,
        battery = get_battery_state(self.config),
        network = get_network_state(self.config),
        weather = weather,
        hn = hn,
        digest_latest = digest_latest,
        show_weather = (not self.config) or self.config:get("show_weather"),
        show_hn = (not self.config) or self.config:get("show_hn"),
        show_digest = show_digest and true or false,
    }
    self.last_state = state
    Logger.info("dashboard", "state_built", {
        has_time = state.time ~= "Time unavailable",
        battery = state.battery,
        network = state.network,
        weather = weather and weather.status or "nil",
        hn = hn and hn.status or "nil",
        hn_items = hn and #(hn.items or {}) or 0,
        digest_latest = digest_latest and digest_latest.date or nil,
    })
    return state
end

local function fmt_epoch(ts)
    if type(ts) ~= "number" then return nil end
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", ts)
    if ok then return s end
    return nil
end

local DASHBOARD_CSS = table.concat({
    "body{font-family:sans-serif;margin:20px;color:#111;background:#fff;}",
    "h1{font-size:30px;margin:0 0 8px 0;}",
    "h2{font-size:22px;margin:0 0 18px 0;font-weight:normal;}",
    ".section{margin:18px 0;padding-top:12px;border-top:1px solid #333;}",
    ".label{font-size:18px;margin:6px 0;}",
    ".muted{font-size:16px;color:#444;margin-top:8px;}",
    "a{color:#111;text-decoration:underline;}",
    ".actions{margin:22px 0 0 0;padding-top:12px;border-top:2px solid #333;}",
    ".action{font-size:19px;margin:12px 0;}",
}, "")

local function safe_href_id(id)
    return tostring(id or ""):gsub("[^%w%-_%.]", "")
end

-- Returns a body fragment (no <html>/<head>): ScrollHtmlWidget wraps it and
-- takes the stylesheet through its `css` option.
local function build_body(state)
    local sections = {
        "<h1>Kindle Home</h1>",
        "<h2>", escape_html(state.date), "</h2>",
        "<div class='label'><b>Time:</b> ", escape_html(state.time), "</div>",
        "<div class='section'>",
        "<div class='label'>", escape_html(state.battery), "</div>",
        "<div class='label'>", escape_html(state.network), "</div>",
        "</div>",
    }

    if state.refresh_hint and state.refresh_hint ~= "" then
        table.insert(sections, "<div class='muted'>" .. escape_html(tostring(state.refresh_hint)) .. "</div>")
    end
    if state.test_article_ready then
        table.insert(sections, "<div class='muted'>Test article saved.</div>")
    end

    if state.show_weather ~= false then
        local weather = state.weather or { status = "error", line = "Weather unavailable." }
        local weather_meta = ""
        if weather.fetched_at then
            local ts = fmt_epoch(weather.fetched_at)
            if ts then weather_meta = "Last update: " .. escape_html(ts); if weather.stale then weather_meta = weather_meta .. " (cached)" end end
        end
        local weather_note = weather.message or Messages.weather(weather.error_kind, weather.status)
        table.insert(sections, "<div class='section'><div class='label'><b>Weather</b></div>")
        table.insert(sections, "<div class='label'>" .. escape_html(weather.line or "Weather unavailable.") .. "</div>")
        if weather_meta ~= "" then table.insert(sections, "<div class='muted'>" .. weather_meta .. "</div>") end
        if weather_note and weather_note ~= "" then table.insert(sections, "<div class='muted'>" .. escape_html(weather_note) .. "</div>") end
        table.insert(sections, "</div>")
    end

    if state.show_hn ~= false then
        local hn = state.hn or { status = "error", line = "HN unavailable.", items = {} }
        local items = hn.items or {}
        local hn_meta = ""
        if hn.fetched_at then
            local ts = fmt_epoch(hn.fetched_at)
            if ts then hn_meta = "Last update: " .. escape_html(ts); if hn.stale then hn_meta = hn_meta .. " (cached)" end end
        end
        local hn_note = hn.message or Messages.hn(hn.error_kind, hn.status, #items > 0)
        table.insert(sections, "<div class='section'><div class='label'><b>Hacker News</b></div>")
        table.insert(sections, "<div class='label'>" .. escape_html(hn.line or "HN unavailable.") .. "</div>")
        if hn_meta ~= "" then table.insert(sections, "<div class='muted'>" .. hn_meta .. "</div>") end
        if hn_note and hn_note ~= "" then table.insert(sections, "<div class='muted'>" .. escape_html(hn_note) .. "</div>") end
        if #items == 0 then
            table.insert(sections, "<div class='muted'>No HN items to show.</div>")
        else
            for _, item in ipairs(items) do
                local title = escape_html(item.title or "(untitled)")
                local rank = tonumber(item.rank) and tostring(item.rank) or "?"
                local meta_parts = {}
                if tonumber(item.score) then table.insert(meta_parts, tostring(item.score) .. " pts") end
                if tonumber(item.descendants) then table.insert(meta_parts, tostring(item.descendants) .. " comments") end
                if item.by and item.by ~= "" then table.insert(meta_parts, "by " .. escape_html(item.by)) end
                if item.domain and item.domain ~= "" then table.insert(meta_parts, escape_html(item.domain)) end
                local status_tag = ""
                if item.status and item.status ~= "ok" then
                    status_tag = " <span class='muted'>[status:" .. escape_html(tostring(item.status)) .. "]</span>"
                elseif not item.has_markdown then
                    status_tag = " <span class='muted'>[no markdown]</span>"
                end
                if item.url == nil then table.insert(meta_parts, "Ask HN") end
                local meta_line = table.concat(meta_parts, " · ")
                table.insert(sections, "<div class='label'><b>" .. escape_html(rank) .. ".</b> " .. title .. status_tag .. "</div>")
                if meta_line ~= "" then table.insert(sections, "<div class='muted'>" .. meta_line .. "</div>") end
            end
        end
        table.insert(sections, "</div>")
    end

    if state.show_digest ~= false then
        local digest = state.digest_latest
        local digest_line = "Daily digest: not generated yet."
        if digest and digest.date then
            digest_line = "Daily digest available: " .. escape_html(digest.date) .. "."
        end
        table.insert(sections, "<div class='section'><div class='label'><b>Digest</b></div>")
        table.insert(sections, "<div class='label'>" .. digest_line .. "</div>")
        table.insert(sections, "<div class='muted'>Generated from cached local, weather, and HN state (partial data supported).</div>")
        table.insert(sections, "</div>")
    end

    -- Actions are plain links: ScrollHtmlWidget has no button support, but it
    -- routes taps on links through html_link_tapped_callback (kh:* scheme).
    table.insert(sections, "<div class='actions'><div class='label'><b>Actions</b></div>")
    table.insert(sections, "<div class='action'><a href='kh:refresh'>Refresh</a></div>")
    if state.show_digest ~= false then
        table.insert(sections, "<div class='action'><a href='kh:digest'>Generate digest</a></div>")
        if state.digest_latest and state.digest_latest.date then
            table.insert(sections, "<div class='action'><a href='kh:digest:latest'>Open latest digest</a></div>")
        end
    end
    if state.show_hn ~= false then
        table.insert(sections, "<div class='action'><a href='kh:test'>Open test article</a></div>")
        for _, item in ipairs((state.hn and state.hn.items) or {}) do
            local id = safe_href_id(item.id)
            if id ~= "" then
                local rank = tonumber(item.rank) or 0
                local title = tostring(item.title or "(untitled)")
                if #title > 42 then title = title:sub(1, 39) .. "..." end
                table.insert(sections, string.format(
                    "<div class='action'><a href='kh:hn:%s'>HN %s: %s</a></div>",
                    id, escape_html(rank > 0 and tostring(rank) or "?"), escape_html(title)))
            end
        end
    end
    table.insert(sections, "<div class='action'><a href='kh:close'>Close</a></div>")
    table.insert(sections, "</div>")

    return table.concat(sections)
end


function Dashboard:open_hn_item(id)
    if id == "test-phase3" then
        self:open_test_article()
        return
    end
    local item = self:get_hn_item(id)
    if not item then
        if self.article_view then
            self.article_view:show({
                title = "Article unavailable",
                status = "not_found",
                meta = { id = tostring(id or ""), status = "not_found", source = "hn" },
            })
        end
        return
    end

    local meta = {
        id = tostring(item.id or ""),
        title = tostring(item.title or "HN article"),
        source = "hnmd",
        date = item.published_at or os.date("%Y-%m-%d"),
        status = tostring(item.status or "ok"),
        hn_url = item.hn_url,
        url = item.url,
        by = item.by,
        score = item.score,
        descendants = item.descendants,
        domain = item.domain,
    }

    if item.status ~= "ok" or not item.has_markdown or item.markdown == "" then
        if self.article_view then
            self.article_view:show({
                title = meta.title,
                status = "no_markdown",
                meta = meta,
                md = (item.markdown and item.markdown ~= "") and item.markdown or nil,
            })
        end
        return
    end

    local doc = nil
    if self.paths and self.article_store then
        self.paths:ensure_base_dirs()
        self.paths:ensure_dir(self.paths:articles_hn_dir())
        local saved, err = self.article_store:save({ kind = "hn", meta = meta, md = item.markdown })
        if saved then
            doc = {
                kind = "hn",
                id = meta.id,
                title = meta.title,
                meta = meta,
                md = item.markdown,
                html = saved.html,
                html_path = saved.html_path,
                md_path = saved.md_path,
                status = "ok",
            }
        else
            Logger.err("dashboard", "hn_article_save_failed", { id = meta.id, err = tostring(err) })
            doc = { title = meta.title, meta = meta, md = item.markdown, status = "ok" }
        end
    else
        doc = { title = meta.title, meta = meta, md = item.markdown, status = "ok" }
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

function Dashboard:handle_link(uri)
    uri = tostring(uri or "")
    if uri == "kh:refresh" then
        if self.actions then
            self.actions:dispatch("refresh", { source = "dashboard", dashboard = self, user_initiated = true })
        else
            self:refresh({ allow_network = false })
        end
        return true
    elseif uri == "kh:close" then
        if self.actions then
            self.actions:dispatch("close", { source = "dashboard", dashboard = self })
        else
            self:close()
        end
        return true
    elseif uri == "kh:digest" then
        if self.actions then
            self.actions:dispatch("generate_digest", { source = "dashboard", dashboard = self })
        end
        return true
    elseif uri == "kh:digest:latest" then
        if self.actions then
            self.actions:dispatch("open_digest:latest", { source = "dashboard", dashboard = self })
        end
        return true
    elseif uri == "kh:test" then
        if self.actions then
            self.actions:dispatch("open_hn:test-phase3", { source = "dashboard", dashboard = self })
        else
            self:open_test_article()
        end
        return true
    end

    local id = uri:match("^kh:hn:(.+)$")
    if id then
        if self.actions then
            self.actions:dispatch("open_hn:" .. id, { source = "dashboard", dashboard = self })
        else
            self:open_hn_item(id)
        end
        return true
    end

    Logger.warn("dashboard", "unknown_link", { uri = uri })
    return false
end

function Dashboard:show(opts)
    opts = opts or {}
    -- Single refresh contract: rebuild local state/body and (re)open the widget.
    -- Note: replacing the widget resets scroll position (accepted in Phase 1).
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    local state = self:build_state(opts)
    state.test_article_ready = self.last_test_doc ~= nil
    if opts.refresh_hint then state.refresh_hint = opts.refresh_hint end

    local widget = ScrollHtmlWidget:new{
        html_body = build_body(state),
        css = DASHBOARD_CSS,
        default_font_size = Screen:scaleBySize(20),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        html_link_tapped_callback = function(link)
            self:handle_link(link and link.uri)
        end,
    }
    -- ScrollHtmlWidget requires `dialog`: its scroll handlers touch
    -- self.dialog.movable and pass it to UIManager:setDirty. Pointing it at
    -- the widget itself is safe (no `movable`) and keeps the dimen valid.
    -- Without it, any swipe/tap raises "attempt to index field 'dialog'".
    widget.dialog = widget
    self.widget = widget
    UIManager:show(widget)
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
