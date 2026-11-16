-- Smoke: the Shell must paint an opaque full-screen background so that stale
-- pixels from the previous screen cannot bleed through the native title bar.
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["device"] = function()
    return { screen = {
        getWidth = function() return 1200 end,
        getHeight = function() return 1600 end,
    } }
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 255 }
end
package.preload["ui/geometry"] = function()
    local Geom = {}
    Geom.__index = Geom
    function Geom:new(o) return setmetatable(o or {}, Geom) end
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
    function M:paintTo(bb, x, y)
        if self[1] and self[1].paintTo then self[1]:paintTo(bb, x, y) end
    end
    return M
end
package.preload["ui/widget/verticalgroup"] = function()
    return { new = function()
        local group = {}
        function group:paintTo(bb, x, y)
            for _, child in ipairs(self) do
                if child.paintTo then child:paintTo(bb, x, y) end
            end
        end
        return group
    end }
end
package.preload["ui/widget/titlebar"] = function()
    return { new = function(o)
        o.getSize = function() return { w = 1200, h = 100 } end
        o.paintTo = function() end
        return o
    end }
end
package.preload["ui/widget/action_bar"] = function()
    return { new = function(o)
        o.getSize = function() return { w = 1200, h = 80 } end
        o.paintTo = function() end
        return o
    end }
end
package.preload["ui/uimanager"] = function()
    return { show = function() end, close = function() end, setDirty = function() end }
end
package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local Shell = dofile(PLUGIN .. "ui/shell.lua")

local rects = {}
local bb = {
    paintRect = function(_, x, y, w, h, color)
        rects[#rects + 1] = { x = x, y = y, w = w, h = h, color = color }
    end,
}

local shell = Shell:new{
    title = "Kindle Home",
    config = { get = function() return true end },
    actions = { { icon = "exit", label = "Exit", callback = function() end } },
    body_factory = function()
        return {
            getCropRegion = function() return nil end,
            paintTo = function() end,
        }
    end,
}

shell:paintTo(bb, 0, 0)
assert(#rects >= 1, "shell must paint a background")
local full = nil
for _, r in ipairs(rects) do
    if r.color == 255 and r.x == 0 and r.y == 0 and r.w == 1200 and r.h == 1600 then
        full = r
    end
end
assert(full, "shell must fill the whole screen with COLOR_WHITE")

print("OK shell paint smoke: full-screen background at 1200x1600")
