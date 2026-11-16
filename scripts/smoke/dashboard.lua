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
    refresh_on_open = false,
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
local shown = 0

package.preload["device"] = function()
    return { screen = flex("screen") }
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

local w = captured_widget
assert(w, "no widget captured")
assert(type(w.html_body) == "string", "html_body missing")
assert(type(w.css) == "string" and #w.css > 0, "css missing")
assert(not w.html_body:find("<html", 1, true), "body must not contain <html>")
assert(not w.html_body:find("<style", 1, true), "body must not contain <style>")
assert(w.html_body:find("Kindle Home", 1, true), "title missing")
assert(w.html_body:find("kh:refresh", 1, true), "refresh link missing")
assert(w.html_body:find("kh:hn:4242", 1, true), "HN link missing")
assert(w.html_body:find("&lt;b&gt;world", 1, true), "HN title should be escaped in link text")
assert(type(w.html_link_tapped_callback) == "function", "link callback missing")
assert(w.dialog == w, "dialog must point to the widget itself")
assert(shown == 1, "widget not shown")

w.html_link_tapped_callback({ uri = "kh:refresh" })
assert(#dispatched == 1 and dispatched[1].id == "refresh", "refresh link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:hn:4242" })
assert(#dispatched == 2 and dispatched[2].id == "open_hn:4242", "HN link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:digest" })
assert(#dispatched == 3 and dispatched[3].id == "generate_digest", "digest link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:close" })
assert(#dispatched == 4 and dispatched[4].id == "close", "close link dispatch failed")
w.html_link_tapped_callback({ uri = "kh:bogus" })

print("OK dashboard smoke: body=" .. #w.html_body .. "B css=" .. #w.css .. "B dispatching=" .. #dispatched)
