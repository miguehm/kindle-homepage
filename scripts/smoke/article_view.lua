-- Smoke test: ui/article_view.lua body build + link wiring on Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local function flex(name)
    return setmetatable({}, {
        __index = function(_, k) return flex(name .. "." .. tostring(k)) end,
        __call = function(_, ...) return flex(name .. "()") end,
        __tostring = function() return "flex:" .. name end,
    })
end

local captured, captured_shell, shown = nil, nil, 0
package.preload["device"] = function()
    return { screen = { scaleBySize = function(_, n) return math.floor(n * 2) end,
        getWidth = function() return 1200 end, getHeight = function() return 1600 end } }
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
    function M:new(o) captured = o; return o end
    return M
end
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(o)
        captured_shell = o
        shown = shown + 1
        return { show = function() end, _closing = false }
    end
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

local v = ArticleView:new{ config = config, actions = actions, on_close = function() closed = true end }

v:show({
    md = "# Hello\n\nBody **bold**.",
    meta = { title = "Hello" },
    on_back = function() back_called = true end,
})

assert(captured_shell, "no shell")
local w = captured_shell.body_factory(1200, 1400)
assert(w, "no widget")
assert(type(w.html_body) == "string")
assert(not w.html_body:find("<html", 1, true), "fragment expected")
assert(not w.html_body:find("kh:back", 1, true), "nav should be native, not HTML")
assert(w.dialog == w, "dialog must be set")
assert(type(w.html_link_tapped_callback) == "function")
assert(type(w.default_font_size) == "number")
assert(shown == 1)

local labels = {}
for _, spec in ipairs(captured_shell.actions or {}) do labels[spec.label] = spec end
assert(labels.Back, "Back action missing")
assert(labels.Close, "Close action missing")
assert(not labels.Reader, "Reader action should be hidden")
labels.Back.callback()
assert(back_called, "back handler failed")

captured_shell = nil
v:show({ status = "missing_path" })
local err_widget = captured_shell.body_factory(1200, 1400)
assert(err_widget and not err_widget.html_body:find("<html", 1, true), "error body must be a fragment")

captured_shell = nil
v:show({ md = "# Two", meta = { title = "Two" } })
for _, spec in ipairs(captured_shell.actions or {}) do
    if spec.label == "Close" then spec.callback() end
end
assert(closed, "close action should call on_close")

print("OK article_view smoke: body=" .. #w.html_body .. "B")
