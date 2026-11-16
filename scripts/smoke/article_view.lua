-- Smoke test: ui/article_view.lua body build + link wiring on Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local function flex(name)
    return setmetatable({}, {
        __index = function(_, k) return flex(name .. "." .. tostring(k)) end,
        __call = function(_, ...) return flex(name .. "()") end,
        __tostring = function() return "flex:" .. name end,
    })
end

local captured, shown = nil, 0
package.preload["device"] = function() return flex("Device") end
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
    function M:new(o) captured = o; return o end
    return M
end
package.preload["apps/reader/readerui"] = function()
    return { showReader = function() end }
end
package.preload["lib/logger"] = function()
    return {
        info = function() end,
        warn = function(m, e) io.stderr:write("WARN ", m, " ", e, "\n") end,
        err = function(m, e) io.stderr:write("ERR ", m, " ", e, "\n") end,
    }
end

local ArticleView = dofile(PLUGIN .. "ui/article_view.lua")

local closed, back_called = false, false
local actions = {
    dispatch = function(_, id)
        if id == "close" then closed = true end
        return true
    end,
}
local config = { get = function(_, k) if k == "open_in_reader_enabled" then return false end end }

local v = ArticleView:new{ config = config, actions = actions }

v:show({
    md = "# Hello\n\nBody **bold**.",
    meta = { title = "Hello" },
    on_back = function() back_called = true end,
})

local w = captured
assert(w, "no widget")
assert(type(w.html_body) == "string")
assert(not w.html_body:find("<html", 1, true), "fragment expected")
assert(w.html_body:find("kh:back", 1, true), "back link missing")
assert(w.html_body:find("kh:dashboard", 1, true), "dashboard link missing")
assert(w.html_body:find("kh:close", 1, true), "close link missing")
assert(not w.html_body:find("kh:reader", 1, true), "reader link should be hidden")
assert(w.dialog == w, "dialog must be set")
assert(type(w.html_link_tapped_callback) == "function")
assert(shown == 1)

w.html_link_tapped_callback({ uri = "kh:back" })
assert(back_called, "back handler failed")
w.html_link_tapped_callback({ uri = "kh:dashboard" })
assert(closed, "dashboard dispatch failed")

-- error state must also be a fragment
captured = nil
v:show({ status = "missing_path" })
assert(captured and not captured.html_body:find("<html", 1, true), "error body must be a fragment")
print("OK article_view smoke: body=" .. #w.html_body .. "B")
