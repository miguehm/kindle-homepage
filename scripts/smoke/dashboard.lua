-- SPDX-License-Identifier: MIT
-- Smoke: native dashboard model + widget tree on plain Lua 5.1.
-- Covers the Paperwhite redesign: combined hero/weather, paged stories,
-- fixed bottom nav, custom header and icon assets.
local PLUGIN = (arg and arg[1] or ".") .. "/"
local SCREEN_W, SCREEN_H = 1200, 1600
local SCROLLBAR = 30

local DashboardModel = require("lib/dashboard_model")

local NOW = 1763289600

local function iso(offset_seconds)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", NOW - offset_seconds)
end

local function fixture_state()
    local items = {}
    for i = 1, 12 do
        items[i] = {
            id = tostring(1000 + i),
            rank = i,
            title = "Headline " .. i,
            score = 10 * i,
            descendants = 3 * i,
            by = "user" .. i,
            domain = "example.com",
            url = "https://example.com/" .. i,
            published_at = iso(i * 3600),
            content_status = "ok",
        }
    end
    items[2].url = nil
    items[2].content_status = "no_content"
    return {
        time = "10:42",
        date = "Monday, November 16, 2026",
        battery = "Battery: 90%, not charging",
        network = "Network: connected (TestNet)",
        weather = {
            status = "ok",
            payload = {
                current_temp = 12.4,
                condition_text = "Cloudy",
                place_name = "Madrid",
                temp_max = 16,
                temp_min = 7,
                wind_kmh = 12,
                humidity = 54,
                icon = "cloud",
                tomorrow_temp_max = 18,
                tomorrow_temp_min = 11,
                tomorrow_icon = "sun",
            },
            fetched_at = NOW - 300,
            stale = true,
        },
        hn = {
            status = "ok",
            items = items,
            fetched_at = NOW - 3600,
            stale = true,
        },
        refreshed_at = NOW - 300,
        refreshed_stale = true,
        show_battery = true,
        show_network = true,
        show_weather = true,
        show_hn = true,
        refresh_hint = "Offline. Turn on WiFi and refresh.",
    }
end

local state = fixture_state()
local model = DashboardModel.build(state, { now = NOW })
assert(model.hero.clock == "10:42" and model.hero.meridiem == "AM", "12h clock missing")
assert(model.hero.date_short ~= "" and model.hero.date_short:upper() == model.hero.date_short, "short date missing")
assert(model.hero.battery_pct == 90 and model.hero.charging == false, "battery missing")
assert(model.hero.wifi == true, "wifi status missing")
assert(model.hero.updated_clock == nil, "freshness belongs to the stories header only")
assert(model.hint == "Offline. Turn on WiFi and refresh.", "hint missing")
assert(model.weather.temp == "12°C" and model.weather.condition == "Cloudy", "weather missing")
assert(model.weather.icon == "cloud" and model.weather.wind == "12 km/h", "weather icon/wind missing")
assert(model.weather.humidity == "54%" and model.weather.place == "Madrid", "weather humidity/place missing")
assert(model.weather.tomorrow.hi == "18°C" and model.weather.tomorrow.lo == "11°C", "tomorrow missing")
assert(model.hn.badge == "Y/HN" and model.hn.title == "TOP STORIES", "stories header missing")
assert(model.hn.pages == 3 and #model.hn.items == 4, "pagination missing")
assert(model.hn.items[1].rank == 1 and model.hn.items[4].rank == 4, "page 1 ranks wrong")
assert(model.hn.items[1].meta:find("example.com", 1, true), "domain missing")
assert(model.hn.items[1].meta:find("10 pts", 1, true), "score missing")
assert(model.hn.items[1].meta:find("3 comments", 1, true), "comments missing")
assert(not model.hn.items[1].meta:find("by user1", 1, true), "author must stay out of the compact meta line")
assert(model.hn.items[1].meta:find("1h", 1, true), "age missing")
local function clock12(ts)
    local h, m = os.date("%H:%M", ts):match("^(%d+):(%d+)")
    h = tonumber(h)
    local display = h % 12
    if display == 0 then display = 12 end
    return string.format("%d:%s %s", display, m, h < 12 and "AM" or "PM")
end
assert(model.hn.refreshed == "Cached " .. clock12(NOW - 300),
    "absolute freshness label missing: " .. tostring(model.hn.refreshed))
local fresh_state = fixture_state()
fresh_state.refreshed_stale = false
assert(DashboardModel.build(fresh_state, { now = NOW }).hn.refreshed == "Updated " .. clock12(NOW - 300),
    "fresh data must read Updated")
assert(DashboardModel.build(state, { now = NOW + 600 }).hn.refreshed == model.hn.refreshed,
    "freshness label must not change as time passes (no per-minute card repaint)")
assert(model.last_refreshed == nil, "obsolete footer model field must be gone")
local notice_state = fixture_state()
notice_state.weather = {
    status = "error",
    line = "Offline. Turn on WiFi and refresh.",
    message = "Offline. Turn on WiFi and refresh.",
}
notice_state.hn.message = "Offline or network error. Showing cached HN."
local notice_model = DashboardModel.build(notice_state, { now = NOW })
assert(notice_model.hint == "Offline. Turn on WiFi and refresh."
    and notice_model.weather.message == nil and notice_model.weather.fallback == nil
    and notice_model.hn.message == nil,
    "global hint must suppress duplicate connectivity notices")
local no_hint_state = fixture_state()
no_hint_state.refresh_hint = nil
no_hint_state.hn.message = "Offline or network error. Showing cached HN."
assert(DashboardModel.build(no_hint_state, { now = NOW }).hn.message ~= nil,
    "source message must survive without a global hint")
assert(#model.nav.tabs == 3 and model.nav.active == "dashboard", "nav model missing")
assert(model.digest == nil and model.footer == nil, "obsolete model fields must be gone")
assert(model.hero.refreshing == false, "hero must not claim to be refreshing by default")
local refreshing_state = fixture_state()
refreshing_state.refreshing = true
local refreshing_model = DashboardModel.build(refreshing_state, { now = NOW })
assert(refreshing_model.hn.refreshing == true,
    "refreshing state must reach the stories header")
assert(refreshing_model.hero.refreshing == false,
    "the hero must not repaint for the indicator while the stories card shows it")
refreshing_state.show_hn = false
assert(DashboardModel.build(refreshing_state, { now = NOW }).hero.refreshing == true,
    "without a stories card the hero carries the indicator")

local page2 = DashboardModel.build(state, { now = NOW, page = 2 })
assert(page2.hn.page == 2 and page2.hn.items[1].rank == 5 and #page2.hn.items == 4, "page 2 wrong")
local page3 = DashboardModel.build(state, { now = NOW, page = 9 })
assert(page3.hn.page == 3 and #page3.hn.items == 4, "page clamp wrong")
local hour24 = DashboardModel.build(state, { now = NOW, clock_24h = true })
assert(hour24.hero.clock == "10:42" and hour24.hero.meridiem == nil, "24h clock wrong")
local hidden_state = fixture_state()
hidden_state.show_weather = false
hidden_state.show_hn = false
hidden_state.show_battery = false
hidden_state.show_network = false
local hidden_model = DashboardModel.build(hidden_state, { now = NOW })
assert(hidden_model.weather == nil and hidden_model.hn == nil, "hidden sections must be absent")
assert(hidden_model.hero.show_battery == false and hidden_model.hero.show_network == false, "hidden chrome wrong")
local empty = fixture_state()
empty.hn.items = {}
local empty_model = DashboardModel.build(empty, { now = NOW })
assert(empty_model.hn.pages == 0 and empty_model.hn.empty == "HN unavailable."
    and empty_model.hn.empty_kind == "error", "empty HN wrong")
local cold = fixture_state()
cold.hn = { status = "error", items = {}, line = "HN unavailable." }
local cold_model = DashboardModel.build(cold, { now = NOW })
assert(cold_model.hn.empty_kind == "not_loaded" and cold_model.hn.empty:find("Not loaded yet", 1, true),
    "a cold start without cache must not claim HN is down")
local worst = DashboardModel.build((function()
    local st = fixture_state()
    st.hn.items[7].title = "A much longer headline that wraps onto a second line easily"
    return st
end)(), { now = NOW, page_size = 2, worst_case = true })
assert(worst.hn.items[1].title:find("much longer", 1, true) and #worst.hn.items == 2,
    "worst-case probe must use the longest titles")
local saved_state = fixture_state()
saved_state.hn.items[1].saved = true
local saved_model = DashboardModel.build(saved_state, { now = NOW })
assert(saved_model.hn.items[1].saved and saved_model.hn.items[1].meta:find("Saved", 1, true),
    "downloaded stories must be marked")
local bad_time = DashboardModel.parse_time("not-a-time")
assert(bad_time == nil, "invalid timestamp must be omitted")

-- ---- KOReader module stubs -------------------------------------------------
local captured, captured_shell, shell_instance, shown, dispatched = nil, nil, nil, 0, {}
local inputs, tap_icons, notices = {}, {}, {}
local dirty_calls, body_updates, UIManager = {}, 0, nil
local region_updates = {}

local function geom(o)
    o = o or {}
    if o.x == nil then o.x = 0 end
    if o.y == nil then o.y = 0 end
    function o:contains() return true end
    return o
end

local function size_of(widget)
    if type(widget.getSize) == "function" then return widget:getSize() end
    return { w = 0, h = 0 }
end

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return math.floor(n * 2) end,
            getWidth = function() return SCREEN_W end,
            getHeight = function() return SCREEN_H end,
        },
        getPowerDevice = function()
            return {
                getCapacity = function() return 90 end,
                isCharging = function() return false end,
            }
        end,
    }
end
package.preload["ui/network/manager"] = function()
    return {
        isConnected = function() return true end,
        getNetworkInfo = function() return { ssid = "TestNet" } end,
        promptWifiOn = function(_, cb) cb() end,
    }
end
package.preload["ui/uimanager"] = function()
    UIManager = {
        show = function(_, w) shown = shown + 1; return w end,
        close = function() end,
        scheduleIn = function() end,
        setDirty = function(_, w, how, region)
            dirty_calls[#dirty_calls + 1] = { widget = w, mode = how, region = region }
        end,
        forceRePaint = function() end,
    }
    return UIManager
end
package.preload["logger"] = function()
    return { dbg = function() end, info = function() end, warn = function() end, err = function() end }
end
package.preload["rapidjson"] = function()
    return {
        encode = function(value)
            return string.format('{"schema_version":%d,"hn_page":%d}',
                tonumber(value.schema_version) or 0, tonumber(value.hn_page) or 0)
        end,
        decode = function(text)
            local schema = tonumber(tostring(text):match('"schema_version"%s*:%s*(%-?%d+)'))
            if not schema then error("invalid json") end
            local page = tonumber(tostring(text):match('"hn_page"%s*:%s*(%-?%d+)'))
            return { schema_version = schema, hn_page = page }
        end,
    }
end
package.preload["ui/widget/infomessage"] = function()
    local M = {}
    function M:new(o) notices[#notices + 1] = o.text; return o end
    return M
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 255, COLOR_BLACK = 0, COLOR_GRAY_6 = 102, COLOR_GRAY_E = 238 }
end
package.preload["ui/font"] = function()
    return { getFace = function(name, size) return { name = name, size = size } end }
end
package.preload["ui/widget/widget"] = function()
    local EventListener = { handleEvent = function() return false end }
    local Widget = {}
    Widget.__index = Widget
    setmetatable(Widget, { __index = EventListener })
    function Widget:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    function Widget:new(o)
        o = self:extend(o)
        if o.init then o:init() end
        return o
    end
    function Widget:getSize() return self.dimen end
    function Widget:paintTo() end
    return Widget
end
package.preload["ui/geometry"] = function()
    local Geom = {}
    Geom.__index = Geom
    function Geom:new(o) return geom(o) end
    return Geom
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/size"] = function()
    return { border = { window = 2 }, line = { thin = 1 } }
end
local TEXT_H = 14
package.preload["ui/widget/textwidget"] = function()
    local M = {}
    function M:new(o)
        o.text = tostring(o.text or "")
        o.getSize = function(self) return { w = math.min(#self.text * 6, 400), h = TEXT_H } end
        return o
    end
    return M
end
package.preload["ui/widget/textboxwidget"] = function()
    local M = {}
    function M:new(o)
        o.text = tostring(o.text or "")
        o.getSize = function(self) return { w = self.width, h = TEXT_H } end
        return o
    end
    return M
end
package.preload["ui/widget/linewidget"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return self.dimen end
        return o
    end
    return M
end
package.preload["ui/widget/verticalspan"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return { w = 0, h = self.width } end
        return o
    end
    return M
end
package.preload["ui/widget/horizontalspan"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return { w = self.width, h = 0 } end
        return o
    end
    return M
end
package.preload["ui/widget/verticalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        function o:getSize()
            local w, h = 0, 0
            for _, child in ipairs(self) do
                local s = size_of(child)
                if s.w > w then w = s.w end
                h = h + s.h
            end
            return { w = w, h = h }
        end
        return o
    end
    return M
end
package.preload["ui/widget/horizontalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        function o:getSize()
            local w, h = 0, 0
            for _, child in ipairs(self) do
                local s = size_of(child)
                w = w + s.w
                if s.h > h then h = s.h end
            end
            return { w = w, h = h }
        end
        return o
    end
    return M
end
package.preload["ui/widget/iconwidget"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return { w = self.width or 24, h = self.height or 24 } end
        return o
    end
    return M
end
package.preload["ui/widget/container/centercontainer"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return self.dimen end
        return o
    end
    return M
end
package.preload["ui/widget/container/leftcontainer"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return self.dimen end
        return o
    end
    return M
end
package.preload["ui/widget/container/framecontainer"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self)
            local s = size_of(self[1])
            local extra = 2 * ((self.bordersize or 0) + (self.padding or 0))
            return { w = s.w + extra, h = s.h + extra }
        end
        return o
    end
    return M
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:getSize() return self.dimen end
    function M:handleEvent() return false end
    function M:paintTo(bb, x, y)
        if self[1] and type(self[1].paintTo) == "function" then
            self[1]:paintTo(bb, x, y)
        end
    end
    function M:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    function M:new(o)
        o = self:extend(o)
        inputs[#inputs + 1] = o
        if o.content_group then o.is_row = true end
        if o.icon or o.file then tap_icons[#tap_icons + 1] = o end
        if o.init then o:init() end
        return o
    end
    return M
end
package.preload["ui/widget/container/scrollablecontainer"] = function()
    local M = { getScrollbarWidth = function() return SCROLLBAR end }
    function M:new(o)
        captured = o
        o.getSize = function(self) return self.dimen end
        o.getCropRegion = function(self) return self.dimen end
        return o
    end
    return M
end
local captured_header
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(o)
        captured_shell = o
        shown = shown + 1
        shell_instance = {
            show = function() UIManager.setDirty(nil, shell_instance, "full") end,
            request_close = function() end, _closing = false,
        }
        if o.header_factory then
            captured_header = o.header_factory(SCREEN_W, shell_instance)
        end
        local factory = o.body_factory
        o.body_factory = function(w, h, parent)
            local body = factory(w, h, parent or shell_instance)
            body.dialog = shell_instance
            body.show_parent = shell_instance
            if type(body.getCropRegion) == "function" then
                shell_instance.cropping_widget = body
            end
            o.body = body
            shell_instance.body = body
            return body
        end
        shell_instance.update_regions = function(_, regions)
            region_updates[#region_updates + 1] = regions
            for _, region in ipairs(regions) do
                UIManager.setDirty(nil, shell_instance, "ui", region)
            end
            return true
        end
        shell_instance.update_body = function()
            body_updates = body_updates + 1
            local body = o.body_factory(SCREEN_W, SCREEN_H - 100, shell_instance)
            local region = type(body.getCropRegion) == "function"
                and body:getCropRegion() or nil
            UIManager.setDirty(nil, shell_instance, "ui", region)
            return true
        end
        return shell_instance
    end
    return M
end
package.preload["lib/refresh"] = function()
    return {
        new_budget = function() return {} end,
        is_in_progress = function() return false end,
        begin = function() return true end,
        finish = function() end,
    }
end
package.preload["lib/weather_state"] = function()
    return { load = function() return fixture_state().weather end }
end
package.preload["lib/hnmd_state"] = function()
    return { load = function() return fixture_state().hn end }
end
package.preload["lib/article_store"] = function()
    return { new = function() return {} end }
end

local cfg = {
    show_battery = true, show_network = true, show_weather = true,
    show_hn = true, refresh_budget_s = 20, hnmd_max_items = 20,
    ui_font_scale = 1.0, ui_fullscreen = true,
    ui_clock_24h = false,
}
local cfg_sets = 0
local cfg_instance = {
    get = function(_, key) return cfg[key] end,
    set = function(_, key, value) cfg_sets = cfg_sets + 1; cfg[key] = value end,
    flush = function() end,
}
local actions = {
    register = function() end,
    dispatch = function(_, id, ctx)
        table.insert(dispatched, { id = id, ctx = ctx })
        return true
    end,
}


-- KOReader propagates touch events to every child of a container; any widget
-- without handleEvent() crashes the whole app on the first tap.
local event_stubs = {
    "ui/widget/textwidget", "ui/widget/textboxwidget", "ui/widget/linewidget",
    "ui/widget/verticalspan", "ui/widget/horizontalspan", "ui/widget/verticalgroup",
    "ui/widget/horizontalgroup", "ui/widget/iconwidget",
    "ui/widget/container/centercontainer", "ui/widget/container/leftcontainer",
    "ui/widget/container/framecontainer", "ui/widget/container/inputcontainer",
    "ui/widget/container/scrollablecontainer",
}
for _, name in ipairs(event_stubs) do
    local module = require(name)
    local original_new = module.new
    module.new = function(self, opts)
        local widget = original_new(self, opts)
        if type(widget.handleEvent) ~= "function" then
            widget.handleEvent = function() return false end
        end
        return widget
    end
end

local function assert_event_tree(widget, label)
    if type(widget) ~= "table" then return end
    if type(widget.getSize) == "function" then
        assert(type(widget.handleEvent) == "function",
            "widget without handleEvent() in tree: " .. tostring(label))
    end
    for i = 1, #widget do
        if type(widget[i]) == "table" then
            assert_event_tree(widget[i], tostring(label) .. "/" .. i)
        end
    end
end

local StoriesCard = require("ui/widget/stories_card")
local Dashboard = dofile(PLUGIN .. "ui/dashboard.lua")
local last_shown_doc
local article_view_stub = {
    will_open_in_reader = function(_, doc) return not not doc.html_path end,
    show = function(_, doc) last_shown_doc = doc end,
}
local ui_state = { page = 1, writes = {} }
function ui_state:get_hn_page() return self.page end
function ui_state:set_hn_page(page)
    self.page = page
    table.insert(self.writes, page)
    return true
end
local function last_ui_write()
    return ui_state.writes[#ui_state.writes]
end
local d = Dashboard:new{
    config = cfg_instance,
    paths = setmetatable({}, { __index = function() return function() return nil end end }),
    actions = actions,
    article_view = article_view_stub,
    plugin_dir = "/mnt/us/koreader/plugins/kindlehome.koplugin",
    ui_state = ui_state,
}
d.article_store = {
    is_local = function() return true end,
    render_derived = function()
        return { ok = true, md_path = "/tmp/a.md", html_path = "/tmp/a.md.html" }
    end,
    load_md = function() return "md" end,
}

local restored_state = { page = 3 }
function restored_state:get_hn_page() return self.page end
function restored_state:set_hn_page(page) self.page = page end
local d_restored = Dashboard:new{ config = cfg_instance, ui_state = restored_state }
assert(d_restored.hn_page == 3, "constructor must restore the persisted page")
local d_default = Dashboard:new{
    config = cfg_instance,
    paths = setmetatable({}, { __index = function() return function() return nil end end }),
}
assert(d_default.hn_page == 1, "missing ui state must default to page 1")

d:show({ allow_network = false })
assert(captured_shell, "no shell captured")
assert(captured_shell.header_factory and captured_header, "custom header missing")
assert(type(captured_header.getSize) == "function" and type(captured_header.paintTo) == "function",
    "header must be a real widget (getSize/paintTo)")
assert(captured_header:getSize().h > 0, "header must report a positive height")
local header_center = captured_header[1][1]
local header_row = header_center[1]
assert(header_center.dimen and header_center.dimen.h == 104,
    "header row must be vertically centered in a fixed band")
assert(header_row[1].width == 40 and header_row[#header_row].width == 40,
    "header margins must be symmetric and match the body margin")
local header_x, close_right = 0, nil
for _, widget in ipairs(header_row) do
    if widget == captured_header.close_button then close_right = header_x + size_of(widget).w end
    header_x = header_x + size_of(widget).w
end
assert(header_x == SCREEN_W, "header row must span the full screen width")
assert(close_right == SCREEN_W - 40, "settings and close must end at the right body margin")
assert(captured_header.settings_button.file and captured_header.settings_button.file:find("/header/settings.svg", 1, true),
    "header settings must use the normalized asset")
assert(captured_header.close_button.file and captured_header.close_button.file:find("/header/close.svg", 1, true),
    "header close must use the normalized asset")
assert(captured_shell.actions == nil, "dashboard must not use the native action bar")
assert(type(captured_shell.body_factory) == "function", "body factory missing")

local function has_text(widget, text)
    if type(widget) ~= "table" then return false end
    if widget.text == text then return true end
    for index = 1, #widget do
        if has_text(widget[index], text) then return true end
    end
    return false
end

local body = captured_shell.body_factory(SCREEN_W, 1400, shell_instance)
assert(body.fits == true and body.scroll == nil, "dashboard must fit 1200x1400 without scrolling")
assert(body.content_width > 0 and body.viewport:getSize().h > 0, "fit viewport wrong")
assert(body.page_size == 4 and body.model == d.model, "fit body must keep four rows and the chosen model")
assert(body.page_size_preferred == 4, "default preferred page size must be four")
assert(body.probes == 1, "default preferred size that fits must use the fast path")
assert(body.nav and body.nav ~= body.viewport, "bottom nav must be outside the content")
assert(body.nav.show_parent == shell_instance, "nav repaint target wrong")
assert(shell_instance.cropping_widget == body, "cropping_widget must be the body wrapper")
assert(body:getCropRegion() == body.dimen, "crop region must be the whole fit body")
assert_event_tree(body, "dashboard-body")
assert(body[1][1] == body.viewport and body[1][2] == body.filler and body[1][3] == body.nav,
    "content must be top-anchored with a filler above the fixed nav")
assert(body.viewport[1] and body.viewport[1].width > 0
    and body.viewport[1].width * 2 + body.content_width == SCREEN_W,
    "left margin is missing from the content row")
assert(size_of(body.filler).h == 0, "stories card must absorb the remaining viewport height")
assert(d.model.hn.refreshed and has_text(body, d.model.hn.refreshed),
    "compact refreshed label must be in the stories header")
assert(not has_text(body, "Last refreshed:"), "obsolete footer label must be gone")
assert(shown == 1, "shell not shown")
assert(dirty_calls[#dirty_calls].widget == shell_instance
    and dirty_calls[#dirty_calls].mode == "full", "opening must use one full refresh")
local repaints_before = #dirty_calls
local updates_before = body_updates
d:show({ state = d.last_state, allow_network = false })
assert(#dirty_calls == repaints_before and body_updates == updates_before,
    "an unchanged refresh must not repaint the screen")

-- Walk the painted body only: layout probes build throwaway cards too.
local function collect(widget, pred, out)
    out = out or {}
    if type(widget) ~= "table" then return out end
    if pred(widget) then out[#out + 1] = widget end
    for i = 1, #widget do collect(widget[i], pred, out) end
    return out
end
local rows = collect(body, function(w) return w.is_row and w.content_group ~= nil and w.on_tap ~= nil
    and w.content_group[1] and w.content_group[1][2] ~= nil end)
local nav_cells = collect(body, function(w) return w.name ~= nil and w.onTapNavCell ~= nil end)
assert(#rows == 4, "expected 4 stories, got " .. tostring(#rows))
assert(body.probes == 1 and d._layout and d._layout.size == 4,
    "the chosen row count must be cached for the layout")
local cached_body = captured_shell.body_factory(SCREEN_W, 1400, shell_instance)
assert(cached_body.probes == 0 and cached_body.page_size == 4,
    "a rebuild with the same layout must reuse the cached row count without probing")
assert(#nav_cells == 3, "expected 3 nav tabs, got " .. tostring(#nav_cells))
for _, cell in ipairs(nav_cells) do
    assert(type(cell.on_tap) == "function" and cell.show_parent == shell_instance, "nav cell wiring wrong")
end
nav_cells[2]:onTapNavCell()
assert(dispatched[#dispatched].id == "nav", "todos tab must dispatch nav")
assert(dispatched[#dispatched].ctx.tab == "todos", "todos tab must target todos")
assert(dispatched[#dispatched].ctx.from == "dashboard", "nav must record origin")
assert(nav_cells[1].active == true and nav_cells[2].active == false, "dashboard nav must stay active until re-shown")
nav_cells[1]:onTapNavCell()

local refreshed = 0
for _, spec in ipairs(dispatched) do
    if spec.id == "refresh" then refreshed = refreshed + 1 end
end
local refresh_icon
for _, icon in ipairs(tap_icons) do
    if type(icon.file) == "string" and icon.file:find("refresh.svg", 1, true) then refresh_icon = icon end
end
assert(refresh_icon and type(refresh_icon.on_tap) == "function" and refresh_icon.icon == nil,
    "two-arrow in-card refresh missing")
refresh_icon.on_tap()
assert(dispatched[#dispatched].id == "refresh", "refresh dispatch failed")

captured_header.close_button.on_tap()
assert(dispatched[#dispatched].id == "close", "header close dispatch failed")
captured_header.settings_button.on_tap()
assert(dispatched[#dispatched].id == "settings", "header settings dispatch failed")

local opened = 0
for _, row in ipairs(rows) do
    if row.on_tap then
        assert(type(row.dimen.contains) == "function", "row dimen must be a Geom")
        row:onTapRow()
        opened = opened + 1
    end
end
assert(opened == 4, "all visible rows must be tappable")
local hn_dispatched = 0
for _, entry in ipairs(dispatched) do
    if entry.id:match("^open_hn:%d+$") then hn_dispatched = hn_dispatched + 1 end
end
assert(hn_dispatched == 4, "HN rows must dispatch open_hn:<id>")

local function pager_icon(name)
    for _, icon in ipairs(tap_icons) do
        if icon.file and icon.file:find(name, 1, true) then return icon end
    end
    return nil
end
local next_icon, prev_icon = pager_icon("next-inverse"), pager_icon("prev-inverse")
assert(next_icon and type(next_icon.on_tap) == "function", "next-page control missing")
assert(prev_icon and type(prev_icon.on_tap) == "function", "previous-page control missing")
assert(next_icon.alpha == true and prev_icon.alpha == true,
    "inverse pager icons must keep their alpha or they flatten to white and vanish")
local body_updates_before_page = body_updates
local region_updates_before_page = #region_updates
local hero_before_page = shell_instance.body:section("hero")
next_icon.on_tap()
assert(d.hn_page == 2 and shown == 1, "next page must repaint in place without refetch or reopening")
assert(body_updates == body_updates_before_page and #region_updates == region_updates_before_page + 1,
    "a page turn must swap one section, not rebuild the body")
local page_regions = region_updates[#region_updates]
assert(#page_regions == 1 and shell_instance.body:section("hero") == hero_before_page,
    "a page turn must repaint only the stories card and keep the hero")
local stories_card = shell_instance.body:section("stories")
assert(page_regions[1].h == size_of(stories_card).h and page_regions[1].y > 0,
    "the page-turn region must be the stories card rectangle")
assert(dirty_calls[#dirty_calls].widget == shell_instance
    and dirty_calls[#dirty_calls].mode == "ui" and dirty_calls[#dirty_calls].region ~= nil,
    "in-place updates must use a regional ui refresh on the top-level shell")
assert(d.model.hn.page == 2 and d.model.hn.items[1].rank == 5, "page 2 content wrong")
prev_icon.on_tap()
assert(d.hn_page == 1, "previous page must return to page 1")
d:set_hn_page(1)
prev_icon.on_tap()
assert(d.hn_page == 3, "previous page must wrap to the last page")
d:set_hn_page(1)

d:set_refreshing(true)
assert(d.refreshing == true, "refreshing flag missing")
assert(has_text(shell_instance.body:section("stories"), "Updating…"),
    "refresh indicator missing from the stories header")
assert(#region_updates[#region_updates] == 1,
    "the refresh indicator must repaint only the stories card")
d:set_refreshing(false)
assert(d.refreshing == false, "refreshing flag must clear")

-- Live clock: a tick repaints the hero card only.
d.last_state.time = "00:00"
d:show({ state = d.last_state, allow_network = false })
local ticks_before = #region_updates
local stories_before_tick = shell_instance.body:section("stories")
d:_on_tick()
assert(#region_updates == ticks_before + 1 and #region_updates[#region_updates] == 1,
    "a clock tick must repaint exactly one region")
assert(shell_instance.body:section("stories") == stories_before_tick,
    "a clock tick must not rebuild the stories card")
assert(region_updates[#region_updates][1].h == size_of(shell_instance.body:section("hero")).h,
    "the clock tick region must be the hero card")
local dirty_before_tick = #dirty_calls
d:_on_tick()
assert(#dirty_calls == dirty_before_tick, "a tick within the same minute must not repaint")

local one_page_state = fixture_state()
one_page_state.hn.items = { one_page_state.hn.items[1], one_page_state.hn.items[2],
                            one_page_state.hn.items[3], one_page_state.hn.items[4] }
local function pager_icon_count()
    local count = 0
    for _, icon in ipairs(tap_icons) do
        if icon.file and (icon.file:find("next-inverse", 1, true)
            or icon.file:find("prev-inverse", 1, true)) then
            count = count + 1
        end
    end
    return count
end
local icons_before = pager_icon_count()
d:show({ state = one_page_state, allow_network = false })
local one_page_body = captured_shell.body_factory(SCREEN_W, 1400, shell_instance)
assert(one_page_body.model.hn.pages == 1, "single-page model wrong")
assert(pager_icon_count() == icons_before, "pager must be hidden when there is only one page")
assert(one_page_body.fits == true, "single-page body must still fit")

d:open_hn_item("1001")
assert(last_shown_doc and last_shown_doc.html_path, "HN doc should carry html_path")
assert(d.widget == shell_instance, "dashboard must stay under ReaderUI")
article_view_stub.will_open_in_reader = function() return false end
d:open_hn_item("1002")
assert(d.widget == nil, "fallback must close the dashboard shell")

d:show({ allow_network = false })
d:set_hn_page(2)
assert(d.hn_page == 2, "page change must update the page")
assert(last_ui_write() == 2, "page change must persist to ui state")
d:show({ allow_network = false })
assert(d.hn_page == 2 and d.model.hn.page == 2,
    "re-show must keep the page without refetching")
d:refresh({ allow_network = false })
assert(d.hn_page == 2, "normal refresh must keep the page")
d:refresh({ allow_network = false, reset_page = true })
assert(d.hn_page == 1, "explicit refresh must reset pagination")
assert(last_ui_write() == 1, "explicit refresh must persist page 1")
d.hn_page = 99
d:show({ allow_network = false })
assert(d.hn_page == 3 and d.model.hn.page == 3,
    "out-of-range page must clamp to the last page")
assert(last_ui_write() == 3, "clamped page must be persisted")
local offline_state = fixture_state()
offline_state.hn.items = {}
offline_state.hn.status = "error"
offline_state.hn.line = "HN unavailable."
d:set_hn_page(2)
d:show({ state = offline_state, allow_network = false })
assert(d.hn_page == 2 and d.model.hn.pages == 0,
    "an empty/offline feed must not overwrite the remembered page")
assert(last_ui_write() == 2, "an empty/offline feed must not persist page 1")
d:show({ allow_network = false })
assert(d.hn_page == 2 and d.model.hn.page == 2,
    "the remembered page must return when the feed is available again")
assert(cfg_sets == 0, "page memory must not write to config")
captured_shell.on_close()
assert(dispatched[#dispatched].id == "close", "shell close should exit dashboard")

d:set_hn_page(1)
TEXT_H = 54
local tight = captured_shell.body_factory(SCREEN_W, 1250, shell_instance)
assert(tight.fits == true and tight.page_size == 3,
    "tall text must degrade from 4 to 3 rows without scrolling")
assert(tight.model.hn.page_size == 3 and #tight.model.hn.items == 3,
    "degraded model must render three rows")

cfg.hn_items_per_page = 10
local wide_pref = captured_shell.body_factory(SCREEN_W, 1250, shell_instance)
assert(wide_pref.page_size == 3 and wide_pref.page_size_preferred == 10,
    "configured preferred size must degrade to the largest fitting size")
assert(wide_pref.probes <= 5, "binary search must bound the number of builds")
assert(wide_pref.model.hn.page_size == 3 and #wide_pref.model.hn.items == 3,
    "degraded configured model must render three rows")
cfg.hn_items_per_page = nil
TEXT_H = 14

-- Forced-overflow path: a short viewport must use the native scroll fallback,
-- reserve the scrollbar width and keep the bottom nav outside the scroll area.
local small = captured_shell.body_factory(SCREEN_W, 500, shell_instance)
assert(small.fits == false and small.scroll == captured, "overflow must use native scroll fallback")
assert(small.page_size == 1 and small.probes <= 5,
    "fallback must settle on one row without unbounded builds")
assert(small.scroll.dimen.w == SCREEN_W and small.scroll.dimen.h > 0, "fallback viewport wrong")
assert(small.content_width < body.content_width, "fallback must reserve scrollbar width")
assert(small.scroll.show_parent == shell_instance and small.scroll.dialog == shell_instance,
    "fallback repaint target wrong")
assert(small:getCropRegion() == small.scroll:getCropRegion(), "fallback crop region wrong")
assert(small[1][1] == small.scroll and small[1][2] == small.nav, "nav must be fixed below the scroll")
assert_event_tree(small, "dashboard-body-fallback")

local function has_next_icon(widget)
    if type(widget) ~= "table" then return false end
    if widget.file and widget.file:find("next-inverse", 1, true) then return true end
    for _, child in ipairs(widget) do
        if has_next_icon(child) then return true end
    end
    return false
end
local function pager_position(card)
    local content = card[1]
    local index, y = nil, 0
    for i, child in ipairs(content) do
        if has_next_icon(child) then index = i; break end
    end
    assert(index, "pager missing from stories card")
    for i = 1, index - 1 do y = y + size_of(content[i]).h end
    return y, index == #content
end
local card_callbacks = {
    show_parent = shell_instance,
    on_refresh = function() end,
    on_open_hn = function() end,
    on_prev_page = function() end,
    on_next_page = function() end,
}
local short_state = fixture_state()
while #short_state.hn.items > 10 do table.remove(short_state.hn.items) end
local short_model = DashboardModel.build(short_state, { now = NOW, page = 3 })
assert(#short_model.hn.items == 2 and short_model.hn.pages == 3, "short page fixture wrong")
local card_long = StoriesCard.build(d.model.hn, cfg_instance, body.content_width, card_callbacks, d.plugin_dir, 900)
local card_short = StoriesCard.build(short_model.hn, cfg_instance, body.content_width, card_callbacks, d.plugin_dir, 900)
assert(size_of(card_long).h == 900 and size_of(card_short).h == 900,
    "stories card must fill the allocated height")
local y_long, last_long = pager_position(card_long)
local y_short, last_short = pager_position(card_short)
assert(y_long == y_short, "pager must not jump when the last page has fewer items")
assert(last_long and last_short, "pager must be the last block of the stories card")

cfg.hn_items_per_page = 2
d:show({ allow_network = false })
local two_rows = captured_shell.body_factory(SCREEN_W, 1400, shell_instance)
assert(two_rows.page_size == 2 and two_rows.page_size_preferred == 2,
    "configured page size must be honored when it fits")
assert(two_rows.probes == 1, "configured size that fits must use the fast path")
assert(#two_rows.model.hn.items == 2 and two_rows.model.hn.pages == 6,
    "configured page size must repaginate the model")
cfg.hn_items_per_page = nil

print("OK dashboard smoke: pages=" .. model.hn.pages .. " rows=" .. tostring(#rows)
    .. " nav=3 fit=1200x" .. tostring(body.viewport:getSize().h)
    .. " fallback=1200x" .. tostring(small.scroll.dimen.h) .. " taps=" .. opened)
