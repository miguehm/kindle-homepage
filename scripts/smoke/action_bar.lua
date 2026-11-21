-- SPDX-License-Identifier: MIT
-- Smoke test: ui/widget/action_bar.lua sizing and tap wiring on Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["device"] = function()
    return { screen = {
        scaleBySize = function(_, n) return math.floor(n * 2) end,
        getWidth = function() return 1200 end,
        getHeight = function() return 1600 end,
    } }
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 0xFFFFFF }
end
package.preload["ui/font"] = function()
    return { getFace = function(name, size) return { name = name, size = size } end }
end
package.preload["ui/geometry"] = function()
    local Geom = {}
    Geom.__index = Geom
    function Geom:new(o) o = o or {}; setmetatable(o, Geom); return o end
    return Geom
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/size"] = function()
    return { border = { button = 2 } }
end
package.preload["ui/uimanager"] = function()
    local state = { dirty = 0 }
    local M = { setDirty = function() state.dirty = state.dirty + 1 end, _state = state }
    return M
end
package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
    function M:new(o) o = self:extend(o); if o.init then o:init() end; return o end
    function M:getSize() return self.dimen end
    return M
end
local function passthrough(name, size)
    local M = {}
    function M:new(o)
        o = o or {}
        o.getSize = function() return size or { w = 10, h = 10 } end
        return o
    end
    return M
end
package.preload["ui/widget/container/centercontainer"] = function()
    local M = {}
    function M:new(o) o = o or {}; return o end
    return M
end
package.preload["ui/widget/container/framecontainer"] = function()
    return passthrough("frame", { w = 10, h = 10 })
end
package.preload["ui/widget/horizontalgroup"] = function()
    return { new = function() return {} end }
end
package.preload["ui/widget/horizontalspan"] = function()
    return passthrough("hspan", { w = 6, h = 0 })
end
package.preload["ui/widget/iconwidget"] = function()
    return passthrough("icon", { w = 48, h = 48 })
end
package.preload["ui/widget/textwidget"] = function()
    return passthrough("text", { w = 60, h = 24 })
end
package.preload["ui/widget/verticalgroup"] = function()
    return { new = function() return {} end }
end
package.preload["ui/widget/verticalspan"] = function()
    return passthrough("vspan", { w = 0, h = 6 })
end

local ActionBar = dofile(PLUGIN .. "ui/widget/action_bar.lua")

local tapped = {}
local bar = ActionBar:new{
    config = { get = function() return 1.0 end },
    buttons = {
        { icon = "cre.render.reload", label = "Refresh", callback = function() tapped[1] = true end },
        { icon = "exit", label = "Exit", callback = function() tapped[2] = true end },
    },
}

assert(bar.dimen and bar.dimen.w > 0 and bar.dimen.h > 0, "action bar must have a size")
local row = bar[1] and bar[1][1] or bar[1]
local buttons = {}
for _, widget in ipairs(row) do
    if widget.onTapActionButton then table.insert(buttons, widget) end
end
assert(#buttons == 2, "two buttons expected, got " .. #buttons)
local total = 0
for _, button in ipairs(buttons) do
    assert(button.width > 0 and button.height > 0, "button needs positive size")
    total = total + button.width
end
assert(total <= 1200, "buttons must fit the screen width")
assert(buttons[1].label == "Refresh" and buttons[2].label == "Exit", "labels wired")
buttons[2]:onTapActionButton()
assert(tapped[2] == true and not tapped[1], "tap should invoke only its own callback")
assert(require("ui/uimanager")._state.dirty == 1, "tap should trigger a repaint")

print("OK action_bar smoke: buttons=" .. #buttons .. " width=" .. total)
