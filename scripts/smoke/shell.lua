-- Smoke test: ui/shell.lua layout, fullscreen hint and exit paths on Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["device"] = function()
    return { screen = {
        scaleBySize = function(_, n) return math.floor(n * 2) end,
        getWidth = function() return 1200 end,
        getHeight = function() return 1600 end,
    } }
end
package.preload["ui/geometry"] = function()
    local Geom = {}
    Geom.__index = Geom
    function Geom:new(o)
        o = o or {}
        setmetatable(o, Geom)
        return o
    end
    return Geom
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    function M:new(o)
        o = self:extend(o)
        if o.init then o:init() end
        return o
    end
    return M
end
package.preload["ui/widget/verticalgroup"] = function()
    return { new = function() return {} end }
end
package.preload["ui/widget/titlebar"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function() return { w = 1200, h = 100 } end
        return o
    end
    return M
end
package.preload["ui/widget/action_bar"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function() return { w = 1200, h = 80 } end
        return o
    end
    return M
end
package.preload["ui/uimanager"] = function()
    local state = { shown = 0, closed = 0, dirty = 0 }
    local M = {
        show = function(_, w) state.shown = state.shown + 1; return w end,
        close = function() state.closed = state.closed + 1 end,
        setDirty = function() state.dirty = state.dirty + 1 end,
    }
    M._state = state
    return M
end
package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local Shell = dofile(PLUGIN .. "ui/shell.lua")
local UIManager = require("ui/uimanager")

local config = { get = function(_, k) if k == "ui_fullscreen" then return true end end }
local body_args = nil
local back_called = false
local closed = false

local shell = Shell:new{
    title = "Kindle Home",
    config = config,
    actions = {
        { icon = "cre.render.reload", label = "Refresh", callback = function() end },
        { icon = "exit", label = "Exit", callback = function() end },
    },
    on_back = function() back_called = true end,
    on_close = function() closed = true end,
    body_factory = function(w, h)
        body_args = { w = w, h = h }
        return { dummy = true }
    end,
}

assert(shell.covers_fullscreen == true, "covers_fullscreen must be set")
assert(body_args and body_args.w == 1200 and body_args.h == 1420, "body must use remaining height")
assert(shell.title_bar.close_callback, "exit icon callback missing")
assert(shell.title_bar.left_icon == "chevron.left", "back icon missing")
assert(shell.action_bar and #shell.action_bar.buttons == 2, "action bar not wired")

shell:show()
assert(UIManager._state.shown == 1, "shell not shown")
assert(UIManager._state.dirty >= 1, "full refresh on show missing")

assert(shell:onBack() == true and back_called, "Back key should call on_back")
assert(shell:onSwipeHeader(nil, { direction = "south" }) == true and UIManager._state.closed == 1, "swipe down should close")
assert(closed == true, "on_close should run on close")

local plain = Shell:new{
    config = { get = function() return false end },
    body_factory = function() return {} end,
}
assert(plain.covers_fullscreen == false, "fullscreen setting should be honored")
assert(plain.title_bar.left_icon == nil, "no back icon without on_back")
assert(plain.action_bar == nil, "no footer without actions")

print("OK shell smoke: body=" .. body_args.w .. "x" .. body_args.h)
