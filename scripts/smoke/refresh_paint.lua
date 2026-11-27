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

-- Section swaps: one "ui" refresh per section rectangle, offset by the header.
shell:show()
local before = #dirty
assert(shell:update_regions({ { x = 40, y = 300, w = 1120, h = 600 } }) == true, "region update failed")
assert(#dirty == before + 1 and last().mode == "ui" and last().region.x == 40
    and last().region.y == 400 and last().region.h == 600,
    "a section swap must refresh only that section, below the header")
assert(shell:region_repainted({ x = 100, y = 450, w = 10, h = 10 }) == true
    and shell:region_repainted({ x = 100, y = 1200, w = 10, h = 10 }) == false,
    "press feedback must know which regions the last update covered")
local generation = shell._body_generation
shell:update_regions({ { x = 0, y = 0, w = 10, h = 10 }, { x = 0, y = 20, w = 10, h = 10 } })
assert(#dirty == before + 3 and shell._body_generation == generation + 1,
    "two swapped sections cost two regional refreshes and one generation bump")

-- Press feedback: invert with "fast" on the control only, restore with "ui"
-- unless the action already repainted a region covering the control.
local PressFeedback = dofile(PLUGIN .. "ui/widget/press_feedback.lua")
local button = { show_parent = shell, dimen = { x = 100, y = 450, w = 96, h = 96 } }
local pressed_during = nil
before = #dirty
PressFeedback.run(button, function() pressed_during = button._pressed end)
assert(pressed_during == true and button._pressed == false, "the control must be inverted while its action runs")
assert(#dirty == before + 2 and dirty[before + 1].mode == "fast" and dirty[before + 1].region.w == 96
    and dirty[before + 2].mode == "ui" and dirty[before + 2].region.w == 96,
    "a press costs one fast refresh of the control and one ui refresh to restore it")
before = #dirty
PressFeedback.run(button, function()
    shell:update_regions({ { x = 0, y = 300, w = 1200, h = 400 } })
end)
assert(#dirty == before + 2 and dirty[before + 2].region.h == 400,
    "no restore refresh when the action repainted the control's section")

-- Tab switch: header and body replaced in the open Shell, one "ui" refresh.
local swapped_header = { getSize = function() return { w = 1200, h = 100 } end, paintTo = function() end }
local closed_before = 0
local swap_ok = shell:swap_content{
    title = "TODO'S",
    header_factory = function() return swapped_header end,
    body_factory = function(w, h) return make_body(w, h) end,
    on_close = function() closed_before = closed_before + 1 end,
}
assert(swap_ok and shell[1][1] == swapped_header and shell.title == "TODO'S",
    "swap_content must replace the header in place")
assert(last().mode == "ui" and last().region == shell.dimen,
    "a tab switch must be one non-flashing refresh of the screen")
local tall_header = { getSize = function() return { w = 1200, h = 140 } end, paintTo = function() end }
assert(shell:swap_content{ header_factory = function() return tall_header end } == false,
    "a header with a different height cannot be swapped in place")

shell:request_close()
assert(last().mode == "full", "closing must refresh fully")

print("OK refresh paint smoke: 7 regional + 1 full, section regions, tab swap ui, open/close full")
