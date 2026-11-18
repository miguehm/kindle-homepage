local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["device"] = function()
    return {
        screen = {
            getSize = function() return { x = 0, y = 0, w = 1200, h = 1600 } end,
        },
    }
end
package.preload["ui/uimanager"] = function()
    return { close = function() end }
end
package.preload["ui/widget/container/centercontainer"] = function()
    return { new = function(_, opts) return opts end }
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, opts) return opts end }
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local InputContainer = {}
    function InputContainer:extend(proto)
        setmetatable(proto, { __index = self })
        proto.__index = proto
        return proto
    end
    function InputContainer:_init()
        self.ges_events = self.ges_events or {}
    end
    function InputContainer:new(o)
        o = o or {}
        setmetatable(o, self)
        if o._init then o:_init() end
        if o.init then o:init() end
        return o
    end
    return InputContainer
end

local ModalPanel = dofile(PLUGIN .. "ui/widget/modal_panel.lua")
local calls = 0
local modal = ModalPanel:new{}
modal.on_close = function() calls = calls + 1 end
local panel = { dimen = { x = 120, y = 500, w = 960, h = 600 } }
modal:set_panel(panel)
assert(modal.ges_events.TapOutside[1].ges == "tap", "modal must close on tap")
assert(modal[1].dimen.w == 1200 and modal[1][1] == panel, "modal must center its panel")

local function pos(x, y)
    return {
        x = x, y = y,
        notIntersectWith = function(self, rect)
            return self.x < rect.x or self.x >= rect.x + rect.w
                or self.y < rect.y or self.y >= rect.y + rect.h
        end,
    }
end

modal:onTapOutside(nil, { pos = pos(10, 10) })
assert(calls == 1, "tap outside must close the modal")
modal:onTapOutside(nil, { pos = pos(600, 700) })
assert(calls == 1, "tap inside the card must not close the modal")

print("OK modal panel smoke: outside tap closes, inside tap is swallowed")
