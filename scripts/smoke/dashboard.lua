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
assert(model.hero.updated_clock, "updated clock missing")
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
assert(model.hn.items[1].meta:find("by user1", 1, true), "author missing")
assert(model.hn.items[1].meta:find("1h", 1, true), "age missing")
assert(model.hn.refreshed == "5 min ago", "compact refreshed label missing")
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
assert(empty_model.hn.pages == 0 and empty_model.hn.empty == "HN unavailable.", "empty HN wrong")
local bad_time = DashboardModel.parse_time("not-a-time")
assert(bad_time == nil, "invalid timestamp must be omitted")

-- ---- KOReader module stubs -------------------------------------------------
local captured, captured_shell, shell_instance, shown, dispatched = nil, nil, nil, 0, {}
local inputs, tap_icons, notices = {}, {}, {}

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
    return {
        show = function(_, w) shown = shown + 1; return w end,
        close = function() end,
        scheduleIn = function() end,
        setDirty = function() end,
        forceRePaint = function() end,
    }
end
package.preload["logger"] = function()
    return { dbg = function() end, info = function() end, warn = function() end, err = function() end }
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
        shell_instance = { show = function() end, request_close = function() end, _closing = false }
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
            return body
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
    ui_font_scale = 1.0, ui_fullscreen = true, ui_show_test_article = true,
    ui_clock_24h = false,
}
local cfg_instance = {
    get = function(_, key) return cfg[key] end,
    set = function() end,
    flush = function() end,
}
local actions = {
    register = function() end,
    dispatch = function(_, id)
        table.insert(dispatched, { id = id })
        return true
    end,
}


-- KOReader propagates touch events to every child of a container; any widget
-- without handleEvent() crashes the whole app on the first tap (F16.10).
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

local Dashboard = dofile(PLUGIN .. "ui/dashboard.lua")
local last_shown_doc
local article_view_stub = {
    will_open_in_reader = function(_, doc) return not not doc.html_path end,
    show = function(_, doc) last_shown_doc = doc end,
}
local d = Dashboard:new{
    config = cfg_instance,
    paths = setmetatable({}, { __index = function() return function() return nil end end }),
    actions = actions,
    article_view = article_view_stub,
    plugin_dir = "/mnt/us/koreader/plugins/kindlehome.koplugin",
}
d.article_store = {
    is_local = function() return true end,
    render_derived = function()
        return { ok = true, md_path = "/tmp/a.md", html_path = "/tmp/a.md.html" }
    end,
    load_md = function() return "md" end,
}

d.last_test_doc = { md_path = "test.md" }
d:show({ allow_network = false })
assert(captured_shell, "no shell captured")
assert(captured_shell.header_factory and captured_header, "custom header missing")
assert(type(captured_header.getSize) == "function" and type(captured_header.paintTo) == "function",
    "header must be a real widget (getSize/paintTo)")
assert(captured_header:getSize().h > 0, "header must report a positive height")
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
assert(d.model.hn.refreshed and has_text(body, d.model.hn.refreshed),
    "compact refreshed label must be in the stories header")
assert(not has_text(body, "Last refreshed:"), "obsolete footer label must be gone")
assert(shown == 1, "shell not shown")

local rows, nav_cells = {}, {}
for _, input in ipairs(inputs) do
    if input.is_row then rows[#rows + 1] = input end
    if input.name then nav_cells[#nav_cells + 1] = input end
end
assert(#rows == 5, "expected 4 stories + dev row, got " .. tostring(#rows))
assert(#nav_cells == 3, "expected 3 nav tabs, got " .. tostring(#nav_cells))
for _, cell in ipairs(nav_cells) do
    assert(type(cell.on_tap) == "function" and cell.show_parent == shell_instance, "nav cell wiring wrong")
end
nav_cells[2]:onTapNavCell()
assert(notices[#notices] == "Coming soon.", "placeholder tab message missing")
assert(nav_cells[1].active == true and nav_cells[2].active == false, "nav active state must not change")
nav_cells[1]:onTapNavCell()

local refreshed = 0
for _, spec in ipairs(dispatched) do
    if spec.id == "refresh" then refreshed = refreshed + 1 end
end
local refresh_icon
for _, icon in ipairs(tap_icons) do
    if icon.icon == "cre.render.reload" then refresh_icon = icon end
end
assert(refresh_icon and type(refresh_icon.on_tap) == "function", "in-card refresh missing")
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
assert(opened == 5, "all visible rows must be tappable")
local hn_dispatched = 0
for _, entry in ipairs(dispatched) do
    if entry.id:match("^open_hn:%d+$") then hn_dispatched = hn_dispatched + 1 end
end
assert(hn_dispatched == 4, "HN rows must dispatch open_hn:<id>")

local next_icon
for _, icon in ipairs(tap_icons) do
    if icon.file and icon.file:find("next-inverse", 1, true) then next_icon = icon end
end
assert(next_icon and type(next_icon.on_tap) == "function", "pager control missing")
next_icon.on_tap()
assert(d.hn_page == 2 and shown > 1, "next page must rebuild without refetch")
assert(d.model.hn.page == 2 and d.model.hn.items[1].rank == 5, "page 2 content wrong")
d:set_hn_page(1)

d:open_hn_item("1001")
assert(last_shown_doc and last_shown_doc.html_path, "HN doc should carry html_path")
assert(d.widget == shell_instance, "dashboard must stay under ReaderUI")
article_view_stub.will_open_in_reader = function() return false end
d:open_hn_item("1002")
assert(d.widget == nil, "fallback must close the dashboard shell")

d:show({ allow_network = false })
d:refresh({ allow_network = false })
assert(d.hn_page == 1, "refresh must reset pagination")
captured_shell.on_close()
assert(dispatched[#dispatched].id == "close", "shell close should exit dashboard")

TEXT_H = 54
local tight = captured_shell.body_factory(SCREEN_W, 1400, shell_instance)
assert(tight.fits == true and tight.page_size == 3,
    "tall text must degrade from 4 to 3 rows without scrolling")
assert(tight.model.hn.page_size == 3 and #tight.model.hn.items == 3,
    "degraded model must render three rows")
TEXT_H = 14

-- Forced-overflow path: a short viewport must use the native scroll fallback,
-- reserve the scrollbar width and keep the bottom nav outside the scroll area.
local small = captured_shell.body_factory(SCREEN_W, 500, shell_instance)
assert(small.fits == false and small.scroll == captured, "overflow must use native scroll fallback")
assert(small.scroll.dimen.w == SCREEN_W and small.scroll.dimen.h > 0, "fallback viewport wrong")
assert(small.content_width < body.content_width, "fallback must reserve scrollbar width")
assert(small.scroll.show_parent == shell_instance and small.scroll.dialog == shell_instance,
    "fallback repaint target wrong")
assert(small:getCropRegion() == small.scroll:getCropRegion(), "fallback crop region wrong")
assert(small[1][1] == small.scroll and small[1][2] == small.nav, "nav must be fixed below the scroll")
assert_event_tree(small, "dashboard-body-fallback")

print("OK dashboard smoke: pages=" .. model.hn.pages .. " rows=" .. tostring(#rows)
    .. " nav=3 fit=1200x" .. tostring(body.viewport:getSize().h)
    .. " fallback=1200x" .. tostring(small.scroll.dimen.h) .. " taps=" .. opened)
