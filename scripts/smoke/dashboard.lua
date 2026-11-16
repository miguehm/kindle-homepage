-- Smoke test: exercise ui/dashboard.lua body build + widget wiring on Lua 5.1
-- with KOReader modules stubbed.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local function flex(name)
    local o = {}
    return setmetatable(o, {
        __index = function(_, k) return flex(name .. "." .. tostring(k)) end,
        __call = function(_, ...) return flex(name .. "()") end,
        __tostring = function() return "flex:" .. name end,
    })
end

local cfg = {
    show_battery = true, show_network = true, show_weather = true,
    show_hn = true, show_digest = true, refresh_budget_s = 20,
    hnmd_max_items = 10, weather_enabled = false, storage_mode = "documents",
    documents_subdir = "KindleHome", open_in_reader_enabled = false,
    refresh_on_open = false, ui_font_scale = 1.0, ui_fullscreen = true,
    ui_show_test_article = false,
}
local cfg_instance = {
    get = function(_, k) return cfg[k] end,
    set = function() end,
    flush = function() end,
}

local dispatched = {}
local actions = {
    register = function() end,
    dispatch = function(_, id, ctx)
        table.insert(dispatched, { id = id, ctx = ctx })
        return true
    end,
}

local captured_widget = nil
local captured_shell = nil
local shown = 0

package.preload["device"] = function()
    return { screen = {
        scaleBySize = function(_, n) return math.floor(n * 2) end,
        getWidth = function() return 1200 end,
        getHeight = function() return 1600 end,
    } }
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
package.preload["ui/widget/scrollhtmlwidget"] = function()
    local M = {}
    function M:new(opts)
        captured_widget = opts
        return opts
    end
    return M
end
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(opts)
        captured_shell = opts
        shown = shown + 1
        return {
            show = function() end,
            request_close = function() end,
        }
    end
    return M
end
package.preload["lib/logger"] = function()
    return {
        info = function(m, e) io.stderr:write("INFO ", m, " ", e, "\n") end,
        warn = function(m, e) io.stderr:write("WARN ", m, " ", e, "\n") end,
        err = function(m, e) io.stderr:write("ERR ", m, " ", e, "\n") end,
    }
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
    return {
        load = function()
            return { status = "configure_location", line = "Weather: configure location in settings.", error_kind = nil }
        end,
    }
end
package.preload["lib/hnmd_state"] = function()
    return {
        load = function()
            return {
                status = "ok", line = "HN: 1 item",
                items = {
                    { id = "4242", rank = 1, title = "Hello <b>world</b> & friends", status = "ok", has_markdown = true, score = 12 },
                },
            }
        end,
    }
end
package.preload["lib/digest"] = function()
    return { latest = function() return nil end }
end
package.preload["lib/article_store"] = function()
    return { new = function() return {} end }
end

local Dashboard = dofile(PLUGIN .. "ui/dashboard.lua")

local d = Dashboard:new{
    config = cfg_instance,
    paths = flex("paths"),
    actions = actions,
    article_view = flex("article_view"),
}

d:show({ allow_network = false })

assert(captured_shell, "no shell captured")
assert(type(captured_shell.body_factory) == "function", "body factory missing")
local w = captured_shell.body_factory(1000, 1400)
assert(w, "no body widget captured")
assert(type(w.html_body) == "string", "html_body missing")
assert(type(w.css) == "string" and #w.css > 0, "css missing")
assert(not w.html_body:find("<html", 1, true), "body must not contain <html>")
assert(not w.html_body:find("<style", 1, true), "body must not contain <style>")
assert(w.html_body:find("WEATHER", 1, true), "weather card missing")
assert(w.html_body:find("HACKER NEWS", 1, true), "HN card missing")
assert(w.html_body:find("kh:hn:4242", 1, true), "HN link missing")
assert(w.html_body:find("&lt;b&gt;world", 1, true), "HN title should be escaped in link text")
assert(w.html_body:find("kh:hn:test-phase3", 1, true) == nil, "test article link should be hidden by default")
assert(type(w.html_link_tapped_callback) == "function", "link callback missing")
assert(w.dialog == w, "dialog must point to the widget itself")
assert(type(w.default_font_size) == "number", "font size should be numeric")
assert(shown == 1, "shell not shown")

local refresh_action
for _, spec in ipairs(captured_shell.actions or {}) do
    if spec.label == "Refresh" then refresh_action = spec end
end
assert(refresh_action and type(refresh_action.callback) == "function", "refresh action missing")
refresh_action.callback()
assert(#dispatched == 1 and dispatched[1].id == "refresh", "refresh action dispatch failed")
w.html_link_tapped_callback({ uri = "kh:hn:4242" })
assert(#dispatched == 2 and dispatched[2].id == "open_hn:4242", "HN link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:digest" })
assert(#dispatched == 3 and dispatched[3].id == "generate_digest", "digest link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:close" })
assert(#dispatched == 4 and dispatched[4].id == "close", "close link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:bogus" })

captured_shell.on_close()
assert(#dispatched == 5 and dispatched[5].id == "close", "shell close should exit dashboard")

print("OK dashboard smoke: body=" .. #w.html_body .. "B css=" .. #w.css .. "B dispatching=" .. #dispatched)
