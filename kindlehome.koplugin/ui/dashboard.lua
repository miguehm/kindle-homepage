local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Logger = require("lib/logger")
local Theme = require("lib/render/theme")
local DashboardHtml = require("lib/render/dashboard_html")
local ArticleStore = require("lib/article_store")
local Refresh = require("lib/refresh")
local WeatherState = require("lib/weather_state")
local HnmdState = require("lib/hnmd_state")
local Digest = require("lib/digest")
local Messages = require("ui/messages")
local Shell = require("ui/shell")

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

function Dashboard:show_notice(text)
    if not text or text == "" then return end
    UIManager:show(InfoMessage:new{ text = text, timeout = 4 })
end

function Dashboard:_article_meta(item)
    return {
        id = tostring(item.id or ""),
        title = tostring(item.title or "HN article"),
        source = "hnmd",
        date = item.published_at or os.date("%Y-%m-%d"),
        status = tostring(item.content_status or "ok"),
        hn_url = item.hn_url,
        url = item.url,
        by = item.by,
        score = item.score,
        descendants = item.descendants,
        domain = item.domain,
    }
end

function Dashboard:_download_article(item)
    local notice = InfoMessage:new{ text = Messages.for_kind("downloading", "Downloading article…") }
    UIManager:show(notice)
    pcall(function() UIManager:forceRePaint() end)
    local res = self.article_store:ensure_local(self.config, item)
    pcall(function() UIManager:close(notice) end)
    return res
end

function Dashboard:open_hn_item(id)
    if id == "test-phase3" then
        self:open_test_article()
        return
    end
    local item = self:get_hn_item(id)
    if not item then
        self:show_notice(Messages.reading("not_found"))
        return
    end
    if not (self.paths and self.article_store) then
        self:show_notice(Messages.reading("content_unavailable"))
        return
    end

    local meta = self:_article_meta(item)
    local md_path = self.paths:article_md_path(item)
    local has_local = self.article_store:is_local(md_path)
    local status = item.content_status or "ok"

    if status ~= "ok" and not has_local then
        if status == "no_content" or status == "warming_up" then
            self:show_notice(Messages.for_kind(status, Messages.reading("content_unavailable")))
        else
            self:show_notice(Messages.reading("content_unavailable"))
        end
        Logger.info("dashboard", "hn_no_content", { id = meta.id, status = status })
        return
    end

    local res
    if has_local then
        local html_path = self.article_store:render_derived(md_path, item, false)
        res = { ok = true, md_path = md_path, html_path = html_path }
        Logger.info("dashboard", "hn_local_hit", { id = meta.id })
    else
        res = self:_download_article(item)
    end

    if not res.ok then
        local kind = res.error_kind
        if (kind == "network" or kind == "timeout") and not res.stale then
            kind = "offline_no_local"
        end
        self:show_notice(Messages.for_kind(kind, Messages.reading("content_unavailable")))
        Logger.warn("dashboard", "hn_open_failed", { id = meta.id, kind = res.error_kind })
        return
    end

    local doc = {
        kind = "hn",
        id = meta.id,
        title = meta.title,
        meta = meta,
        status = "ok",
        md_path = res.md_path,
        html_path = res.html_path,
        on_back = function() self:show({ allow_network = false }) end,
    }
    if not doc.html_path then
        -- Render failure: hand the raw Markdown to the in-plugin viewer rather
        -- than blocking the item entirely.
        local md = self.article_store:load_md(res.md_path)
        doc.md = md or ""
    end

    self:_teardown()
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
    self:_teardown()
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

function Dashboard:_teardown()
    local widget = self.widget
    if not widget then return end
    self.widget = nil
    -- Programmatic close: suppress the shell's user-close callback.
    widget._closing = true
    widget.on_close = nil
    widget.on_back = nil
    pcall(function() UIManager:close(widget) end)
end

function Dashboard:actions_for_state(state)
    local specs = {
        {
            icon = "cre.render.reload",
            label = "Refresh",
            callback = function() self:handle_link("kh:refresh") end,
        },
    }
    if state.show_digest ~= false then
        table.insert(specs, {
            icon = "book.opened",
            label = "Digest",
            callback = function() self:handle_link("kh:digest") end,
        })
    end
    table.insert(specs, {
        icon = "exit",
        label = "Exit",
        callback = function() self:handle_link("kh:close") end,
    })
    return specs
end

function Dashboard:_shell_close()
    self.widget = nil
    if self.actions then
        self.actions:dispatch("close", { source = "dashboard", dashboard = self })
    end
end

function Dashboard:show(opts)
    opts = opts or {}
    self:_teardown()

    local state = self:build_state(opts)
    state.test_article_ready = self.last_test_doc ~= nil
    if opts.refresh_hint then state.refresh_hint = opts.refresh_hint end

    local show_test = not self.config or self.config:get("ui_show_test_article") == true
    local body_html = DashboardHtml.build(state, { test_article_ready = show_test and state.test_article_ready })
    local css = Theme.dashboard_css()
    local font_size = Theme.font_size(self.config, Theme.UI_BASE)

    local shell = Shell:new{
        title = "Kindle Home",
        config = self.config,
        actions = self:actions_for_state(state),
        on_close = function() self:_shell_close() end,
        on_layout_change = function() self:show(opts) end,
        body_factory = function(width, height)
            local body = ScrollHtmlWidget:new{
                html_body = body_html,
                css = css,
                default_font_size = font_size,
                width = width,
                height = height,
                html_link_tapped_callback = function(link)
                    self:handle_link(link and link.uri)
                end,
            }
            -- ScrollHtmlWidget requires `dialog`: its scroll handlers touch
            -- self.dialog.movable and pass it to UIManager:setDirty. Pointing
            -- it at the widget itself is safe (no `movable`).
            body.dialog = body
            return body
        end,
    }
    self.widget = shell
    shell:show()
    Logger.info("dashboard", "shown", { weather = state.weather and state.weather.status })
end

function Dashboard:refresh(opts)
    Logger.info("dashboard", "refresh", { allow_network = opts and opts.allow_network })
    self:show(opts)
end

function Dashboard:close()
    self:_teardown()
    Logger.info("dashboard", "closed")
end

return Dashboard
