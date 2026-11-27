-- SPDX-License-Identifier: MIT
-- Smoke: minimum screen updates. In-place body swaps repaint only the body
-- region with a non-flashing "ui" refresh; every 8th swap is promoted to a
-- full refresh to clear e-ink ghosting. Opening and closing stay full.
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
        function group:resetLayout() self.reset_calls = (self.reset_calls or 0) + 1 end
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
local dirty
package.preload["ui/uimanager"] = function()
    dirty = {}
    return {
        show = function() end,
        close = function() end,
        setDirty = function(_, widget, mode, region)
            dirty[#dirty + 1] = { widget = widget, mode = mode, region = region }
        end,
    }
end
package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local Shell = dofile(PLUGIN .. "ui/shell.lua")
local builds = 0
local function make_body(w, h)
    builds = builds + 1
    return {
        getSize = function() return { w = w, h = h } end,
        getCropRegion = function() return { x = 0, y = 0, w = w, h = h } end,
        paintTo = function() end,
    }
end
local shell = Shell:new{
    config = { get = function() return true end },
    header_factory = function()
        return { getSize = function() return { w = 1200, h = 100 } end, paintTo = function() end }
    end,
    body_factory = function(w, h) return make_body(w, h) end,
}
local function last() return dirty[#dirty] end

shell:show()
assert(last().widget == shell and last().mode == "full" and last().region == nil,
    "opening must be one full refresh")
assert(builds == 1, "initial body built once")

for i = 1, 7 do
    assert(shell:update_body() == true, "in-place update failed")
    assert(last().widget == shell and last().mode == "ui", "in-place update must mark the shell ui-dirty")
    assert(last().region and last().region.x == 0 and last().region.y == 100
        and last().region.w == 1200 and last().region.h == 1500,
        "in-place update must refresh only the body slice below the header")
end
assert(builds == 8, "each in-place update must rebuild only the body")
assert(shell[1].reset_calls == 7, "the layout must be reset after each body swap")

shell:update_body()
assert(last().mode == "full" and last().region == nil, "every 8th update must be a full refresh")
shell:update_body()
assert(last().mode == "ui", "the full refresh counter must reset")

shell:show()
assert(last().mode == "full", "re-showing must refresh fully")
shell:update_body()
assert(last().mode == "ui", "show must reset the promotion counter")

local supplied = make_body(1200, 1500)
shell:update_body({ body = supplied })
assert(shell.body == supplied and shell[1][shell.body_index] == supplied
    and supplied.dialog == shell and supplied.show_parent == shell,
    "a supplied body must be adopted and wired to the shell")

shell:request_close()
assert(last().mode == "full", "closing must refresh fully")

print("OK refresh paint smoke: 7 regional + 1 full, region=0/100/1200/1500, open/close full")
