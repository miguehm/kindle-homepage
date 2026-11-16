-- Smoke test: ui/article_view.lua fallback wiring to the native HTML pager.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local captured, captured_shell, shell_instance, shown = nil, nil, nil, 0
local READER_THROW = false

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return math.floor(n * 2) end,
            getWidth = function() return 1200 end,
            getHeight = function() return 1600 end,
        },
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
package.preload["ui/article_html_pager"] = function()
    local M = {}
    function M:new(o) captured = o; return o end
    return M
end
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(o)
        captured_shell = o
        shown = shown + 1
        shell_instance = { show = function() end, _closing = false }
        local factory = o.body_factory
        o.body_factory = function(w, h)
            local body = factory(w, h)
            body.dialog = shell_instance
            body.show_parent = shell_instance
            if body.htmlbox_widget then body.htmlbox_widget.dialog = shell_instance end
            o.body = body
            return body
        end
        return shell_instance
    end
    return M
end
package.preload["apps/reader/readerui"] = function()
    return {
        showReader = function()
            if READER_THROW then error("reader failed") end
        end,
    }
end
package.preload["lib/logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
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
local config = { get = function() return nil end }

local v = ArticleView:new{ config = config, actions = actions, on_close = function() closed = true end }

v:show({
    md = "# Hello\n\nBody **bold**.",
    meta = { title = "Hello" },
    on_back = function() back_called = true end,
})

assert(captured_shell, "no shell")
local w = captured_shell.body_factory(1200, 1400)
assert(w, "no pager")
assert(w.width == 1200 and w.height == 1400, "pager must fill the body area")
assert(type(w.body) == "string" and #w.body > 0, "body missing")
assert(not w.body:find("<html", 1, true), "fragment expected")
assert(not w.body:find("kh:back", 1, true), "nav should be native, not HTML")
assert(type(w.css) == "string" and #w.css > 0, "css missing")
assert(type(w.font_size) == "number", "font size missing")
assert(type(w.on_link) == "function", "link callback missing")
assert(w.html_body == nil and w.default_font_size == nil, "no ScrollHtmlWidget options")
assert(w.dialog == shell_instance and w.dialog ~= w, "dialog must point to the top-level shell")
assert(w.show_parent == shell_instance, "show_parent must point to the top-level shell")
assert(shown == 1)

local labels = {}
for _, spec in ipairs(captured_shell.actions or {}) do labels[spec.label] = spec end
assert(labels.Back, "Back action missing")
assert(labels.Close, "Close action missing")
assert(not labels.Reader, "Reader action should be hidden")
w.on_link({ uri = "kh:back" })
assert(back_called, "pager link callback failed")

captured_shell = nil
v:show({ status = "missing_path" })
local err_widget = captured_shell.body_factory(1200, 1400)
assert(err_widget and type(err_widget.body) == "string", "error body missing")
assert(not err_widget.body:find("<html", 1, true), "error body must be a fragment")

captured_shell = nil
v:show({ md = "# Two", meta = { title = "Two" } })
for _, spec in ipairs(captured_shell.actions or {}) do
    if spec.label == "Close" then spec.callback() end
end
assert(closed, "close action should call on_close")

local forced = ArticleView:new{
    config = { get = function(_, key) return key == "ui_force_article_fallback" end },
    actions = actions,
}
captured_shell = nil
forced:show({ html_path = "/tmp/article.md.html", meta = { title = "Forced" } })
assert(captured_shell, "ui_force_article_fallback must bypass ReaderUI")

local fallback_called = false
local reader_view = ArticleView:new{ config = config, actions = actions }
assert(reader_view:will_open_in_reader({ html_path = "/tmp/a.html" }) == true)
assert(reader_view:will_open_in_reader({}) == false)
captured_shell = nil
reader_view:show({
    html_path = "/tmp/a.html",
    meta = { title = "Reader" },
    on_fallback = function() fallback_called = true end,
})
assert(captured_shell == nil, "ReaderUI path must not show the fallback shell")
assert(fallback_called == false, "successful ReaderUI must not call on_fallback")

READER_THROW = true
captured_shell = nil
reader_view:show({
    html_path = "/tmp/b.html",
    meta = { title = "Reader" },
    on_fallback = function() fallback_called = true end,
})
assert(fallback_called == true, "failed ReaderUI must call on_fallback")
assert(captured_shell, "failed ReaderUI must show the fallback shell")

print("OK article_view smoke: pager body=" .. #w.body .. "B reader return OK")
