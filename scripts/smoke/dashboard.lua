-- Smoke test: native dashboard model + widget tree on plain Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local DashboardModel = require("lib/dashboard_model")

local NOW = 1763289600

local function fixture_state()
    local items = {}
    for i = 1, 10 do
        items[i] = {
            id = tostring(1000 + i),
            rank = i,
            title = "Headline " .. i,
            score = 10 * i,
            descendants = 3 * i,
            by = "user" .. i,
            domain = "example.com",
            url = "https://example.com/" .. i,
            content_status = "ok",
        }
    end
    items[2].url = nil
    items[2].content_status = "no_content"
    return {
        time = "12:34",
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
        digest_latest = { date = "2026-11-16" },
        show_weather = true,
        show_hn = true,
        show_digest = true,
        refresh_hint = "Offline. Turn on WiFi and refresh.",
    }
end

local model = DashboardModel.build(fixture_state(), { now = NOW, test_article_ready = true })
assert(model.hero.clock == "12:34", "clock missing")
assert(model.hero.date == "Monday, November 16, 2026", "date missing")
assert(model.status and model.status:find("Battery: 90%", 1, true), "battery missing")
assert(model.status and model.status:find("TestNet", 1, true), "network missing")
assert(model.hint == "Offline. Turn on WiFi and refresh.", "hint missing")
assert(model.weather.temp == "12°C", "temperature missing")
assert(model.weather.condition == "Cloudy", "condition missing")
assert(model.weather.detail and model.weather.detail:find("Madrid", 1, true), "place missing")
assert(model.weather.detail and model.weather.detail:find("H:16°C L:7°C", 1, true), "min/max missing")
assert(model.weather.updated == "Updated 5 min ago · cached", "weather updated missing")
assert(#model.hn.items == 10, "HN rows missing")
assert(model.hn.items[1].meta:find("10 pts", 1, true), "score missing")
assert(model.hn.items[1].meta:find("3 comments", 1, true), "comments missing")
assert(model.hn.items[1].meta:find("by user1", 1, true), "author missing")
assert(model.hn.items[2].meta:find("Ask HN", 1, true), "Ask HN missing")
assert(model.hn.items[2].meta:find("unavailable", 1, true), "unavailable flag missing")
assert(model.hn.updated == "Updated 1 h ago · cached", "HN updated missing")
assert(model.digest.available and model.digest.date == "2026-11-16", "digest state missing")
assert(model.digest.link == nil and model.digest.url == nil, "digest must have no link")
assert(not model.footer:find("Open latest digest", 1, true), "digest link in footer")
assert(model.test_article == true, "test article row missing")

local hidden = fixture_state()
hidden.show_weather = false
hidden.show_hn = false
hidden.show_digest = false
local hidden_model = DashboardModel.build(hidden, { now = NOW })
assert(hidden_model.weather == nil and hidden_model.hn == nil and hidden_model.digest == nil, "hidden sections must be absent")

local empty = fixture_state()
empty.hn.items = {}
local empty_model = DashboardModel.build(empty, { now = NOW })
assert(empty_model.hn.empty == "HN unavailable.", "empty HN message missing")

local captured, captured_shell, shell_instance, shown, dispatched = nil, nil, nil, 0, {}
local rows = {}

local function geom(o)
    o = o or {}
    if o.x == nil then o.x = 0 end
    if o.y == nil then o.y = 0 end
    function o:contains() return true end
    return o
end

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return math.floor(n * 2) end,
            getWidth = function() return 1200 end,
            getHeight = function() return 1600 end,
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
    }
end
package.preload["logger"] = function()
    return {
        dbg = function() end,
        info = function() end,
        warn = function() end,
        err = function() end,
    }
end
package.preload["ui/widget/infomessage"] = function()
    local M = {}
    function M:new(opts) return opts end
    return M
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 1 }
end
package.preload["ui/font"] = function()
    return { getFace = function() return {} end }
end
package.preload["ui/geometry"] = function()
    return { new = function(_, o) return geom(o) end }
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/size"] = function()
    return { border = { window = 2 }, line = { thin = 1 } }
end
package.preload["ui/widget/textboxwidget"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self) return { w = self.width, h = 12 } end
        return o
    end
    return M
end
package.preload["ui/widget/textwidget"] = function()
    local M = {}
    function M:new(o)
        o.text = tostring(o.text or "")
        o.getSize = function(self) return { w = math.min(#self.text * 3, 200), h = 12 } end
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
package.preload["ui/widget/verticalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        setmetatable(o, { __index = M })
        function o:getSize()
            local w, h = 0, 0
            for _, child in ipairs(self) do
                local s = child:getSize()
                if s.w > w then w = s.w end
                h = h + s.h
            end
            return { w = w, h = h }
        end
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
            local s = self[1]:getSize()
            local extra = 2 * (self.bordersize + self.padding)
            return { w = s.w + extra, h = s.h + extra }
        end
        return o
    end
    return M
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:getSize() return self.dimen end
    function M:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    function M:new(o)
        o = self:extend(o)
        if o._init then o:_init() end
        if o.init then o:init() end
        if o.content_group then table.insert(rows, o) end
        return o
    end
    return M
end
package.preload["ui/widget/container/scrollablecontainer"] = function()
    local M = { getScrollbarWidth = function() return 30 end }
    function M:new(o)
        captured = o
        o.getSize = function(self) return self.dimen end
        o.getCropRegion = function(self) return self.dimen end
        return o
    end
    return M
end
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(opts)
        captured_shell = opts
        shown = shown + 1
        local instance = { show = function() end, request_close = function() end, _closing = false }
        shell_instance = instance
        local factory = opts.body_factory
        opts.body_factory = function(w, h)
            local body = factory(w, h)
            body.dialog = instance
            body.show_parent = instance
            if type(body.getCropRegion) == "function" then
                instance.cropping_widget = body
            end
            opts.body = body
            return body
        end
        return instance
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
package.preload["lib/digest"] = function()
    return { latest = function() return { date = "2026-11-16" } end }
end
package.preload["lib/article_store"] = function()
    return { new = function() return {} end }
end

local cfg = {
    show_battery = true, show_network = true, show_weather = true,
    show_hn = true, show_digest = true, refresh_budget_s = 20,
    hnmd_max_items = 10, ui_font_scale = 1.0, ui_fullscreen = true,
    ui_show_test_article = true,
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
assert(type(captured_shell.body_factory) == "function", "body factory missing")
local body = captured_shell.body_factory(1200, 1400)
assert(captured == body, "ScrollableContainer not captured")
assert(body.dimen.w == 1200 and body.dimen.h == 1400, "scroll viewport must fill body area")
assert(#body == 1, "ScrollableContainer needs a single child")
assert(body[1].dimen.w == 1170, "content width must exclude scrollbar width")
assert(body[1].dimen.h > 0, "content height must be measured")
assert(body.dialog == shell_instance and body.show_parent == shell_instance, "repaint target must be the shell")
assert(shell_instance.cropping_widget == body, "cropping_widget must be the scroll container")
assert(shown == 1, "shell not shown")

local tapped = 0
for _, row in ipairs(rows) do
    if row.on_tap then
        assert(type(row.dimen.contains) == "function", "row dimen must be a Geom for gesture ranges")
        row:onTapHnRow()
        tapped = tapped + 1
    end
end
assert(tapped == 11, "expected 10 HN rows + 1 test row, got " .. tapped)
local hn_dispatched = 0
for _, entry in ipairs(dispatched) do
    if entry.id:match("^open_hn:") then hn_dispatched = hn_dispatched + 1 end
end
assert(hn_dispatched == 11, "HN and test rows must dispatch open_hn:<id>")

d:open_hn_item("1001")
assert(last_shown_doc and last_shown_doc.html_path, "HN doc should carry html_path")
assert(d.widget == shell_instance, "dashboard must stay under ReaderUI")
article_view_stub.will_open_in_reader = function() return false end
d:open_hn_item("1002")
assert(d.widget == nil, "fallback must close the dashboard shell")

local refresh_action
for _, spec in ipairs(captured_shell.actions or {}) do
    if spec.label == "Refresh" then refresh_action = spec end
end
assert(refresh_action and type(refresh_action.callback) == "function", "refresh action missing")
refresh_action.callback()
assert(dispatched[#dispatched].id == "refresh", "refresh action dispatch failed")
captured_shell.on_close()
assert(dispatched[#dispatched].id == "close", "shell close should exit dashboard")

print("OK dashboard smoke: model rows=" .. #model.hn.items .. " native viewport=1200x1400 taps=" .. tapped)
