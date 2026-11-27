-- SPDX-License-Identifier: MIT
-- Body container shared by the dashboard and TODO'S views.
--
-- - Reports the content area (or the scroll fallback's) as its crop region
--   so KOReader repaints the right framebuffer slice.
-- - Remembers where each named section sits, so a state change that touches
--   one section (a page turn, a clock tick, a filter) swaps only that widget
--   and refreshes only its rectangle instead of rebuilding the whole body.
-- - Pages the card list on horizontal swipes when the body fits the screen.
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local BodyWrapper = InputContainer:extend{
    scroll = nil,
    sections = nil, -- key -> { group, index, x, y }
    on_next_page = nil,
    on_prev_page = nil,
}

function BodyWrapper:getCropRegion()
    if self.scroll and type(self.scroll.getCropRegion) == "function" then
        return self.scroll:getCropRegion()
    end
    return self.dimen
end

-- Record a section placed at `group[index]`, offset (x, y) inside the body.
function BodyWrapper:track_section(key, group, index, x, y)
    self.sections = self.sections or {}
    self.sections[key] = { group = group, index = index, x = x, y = y }
end

function BodyWrapper:section(key)
    local entry = self.sections and self.sections[key]
    return entry and entry.group[entry.index] or nil
end

-- Swap one section in place. Returns the body-relative region to refresh, or
-- nil when the swap would move other sections (different height) or the body
-- scrolls; the caller then rebuilds the whole body instead.
function BodyWrapper:replace_section(key, widget)
    if self.scroll or not widget then return nil end
    local entry = self.sections and self.sections[key]
    if not entry then return nil end
    local old = entry.group[entry.index]
    if not old then return nil end
    local old_size = old:getSize()
    local new_size = widget:getSize()
    if old_size.h ~= new_size.h or old_size.w ~= new_size.w then return nil end
    entry.group[entry.index] = widget
    if type(old.free) == "function" then old:free() end
    if type(entry.group.resetLayout) == "function" then entry.group:resetLayout() end
    return Geom:new{ x = entry.x, y = entry.y, w = new_size.w, h = new_size.h }
end

function BodyWrapper:enable_swipe(on_next_page, on_prev_page)
    self.on_next_page = on_next_page
    self.on_prev_page = on_prev_page
    self.ges_events = {
        SwipeBody = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            },
        },
    }
end

function BodyWrapper:onSwipeBody(_, ges)
    if self.scroll or not ges then return false end
    if ges.direction == "west" and type(self.on_next_page) == "function" then
        self.on_next_page()
        return true
    end
    if ges.direction == "east" and type(self.on_prev_page) == "function" then
        self.on_prev_page()
        return true
    end
    return false
end

return BodyWrapper
