-- SPDX-License-Identifier: MIT
-- Highlight-then-act press feedback (DESIGN.md "instant binary inversion").
--
-- 1. Mark the control as pressed and refresh only its rectangle with the
--    "fast" waveform. The inversion is pure black/white, so the fast (A2/DU)
--    waveform renders it without gray artifacts.
-- 2. Flush that refresh before running the callback, so the user sees the
--    press even when the callback blocks (network, dialogs).
-- 3. Run the callback.
-- 4. Restore the control with a "ui" refresh of the same rectangle, unless the
--    callback closed the Shell or already repainted a region that covers it.
--
-- Never flags the whole Shell: every refresh carries the control's region.
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local PressFeedback = {}

local function region_of(widget)
    local d = widget and widget.dimen
    if not d or not d.w or not d.h or d.w <= 0 or d.h <= 0 then return nil end
    return Geom:new{ x = d.x or 0, y = d.y or 0, w = d.w, h = d.h }
end

-- Paint hook: call after the child has been painted at (x, y).
function PressFeedback.paint(widget, bb, x, y)
    if not widget._pressed or not bb or type(bb.invertRect) ~= "function" then return end
    local d = widget.dimen
    if d and d.w and d.h then bb:invertRect(x, y, d.w, d.h) end
end

function PressFeedback.run(widget, callback, ...)
    local parent = widget and widget.show_parent
    local region = region_of(widget)
    local flash = parent ~= nil and parent ~= widget and region ~= nil and not parent._closing
    local generation = parent and parent._body_generation
    if flash then
        widget._pressed = true
        UIManager:setDirty(parent, "fast", region)
        if type(UIManager.forceRePaint) == "function" then
            pcall(function() UIManager:forceRePaint() end)
        end
    end
    if type(callback) == "function" then callback(...) end
    if not flash then return true end
    widget._pressed = false
    if parent._closing then return true end
    if parent._body_generation ~= generation and type(parent.region_repainted) == "function"
            and parent:region_repainted(region) then
        return true
    end
    UIManager:setDirty(parent, "ui", region)
    return true
end

return PressFeedback
