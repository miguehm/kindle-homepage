-- Smoke test: ui/article_html_pager.lua input and page navigation on Lua 5.1.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local PAGE_COUNT = 3
local dirty_calls, last_dirty_widget = 0, nil

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return math.floor(n * 2) end,
            getWidth = function() return 1200 end,
            getHeight = function() return 1600 end,
        },
        isTouchDevice = function() return true end,
        hasKeys = function() return true end,
        input = { group = { PgBack = {}, PgFwd = {} } },
    }
end
package.preload["ui/geometry"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        if o.x == nil then o.x = 0 end
        if o.y == nil then o.y = 0 end
        function o:contains() return true end
        function o:intersectWith() return true end
        return o
    end
    return M
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/widget/horizontalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        o.getSize = function() return { w = 1200, h = 1400 } end
        return o
    end
    return M
end
package.preload["ui/widget/horizontalspan"] = function()
    local M = {}
    function M:new(o) return o end
    return M
end
package.preload["ui/widget/htmlboxwidget"] = function()
    local M = {}
    function M:new(o)
        o.page_count = PAGE_COUNT
        o.page_number = 1
        o.dimen = o.dimen or { w = 1180, h = 1400 }
        o.freed = 0
        function o:setContent(body, css, font_size)
            self.rendered = { body = body, css = css, font_size = font_size }
        end
        function o:setPageNumber(page) self.page_number = page end
        function o:freeBb() self.freed = self.freed + 1 end
        function o:getSize() return self.dimen end
        return o
    end
    return M
end
package.preload["ui/widget/verticalscrollbar"] = function()
    local M = {}
    function M:new(o)
        o.low, o.high = 0, 1
        function o:set(low, high) self.low, self.high = low, high end
        function o:getSize() return { w = self.width, h = self.height } end
        return o
    end
    return M
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:getSize() return self.dimen end
    function M:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        return o
    end
    function M:new(o)
        o = self:extend(o)
        if o._init then o:_init() end
        if o.init then o:init() end
        return o
    end
    return M
end
package.preload["ui/uimanager"] = function()
    return {
        setDirty = function(_, widget)
            dirty_calls = dirty_calls + 1
            last_dirty_widget = widget
        end,
    }
end

local Pager = dofile(PLUGIN .. "ui/article_html_pager.lua")

local show_parent = {}
local seen_link = nil
local pager = Pager:new{
    width = 1200,
    height = 1400,
    body = "fragment",
    css = "css",
    font_size = 42,
    on_link = function(link) seen_link = link and link.uri end,
}
pager.show_parent = show_parent

assert(pager.dimen.w == 1200 and pager.dimen.h == 1400, "pager must fill the body area")
assert(pager.htmlbox_widget.rendered.body == "fragment", "content not set")
assert(pager.htmlbox_widget.rendered.css == "css", "css not passed")
assert(pager.htmlbox_widget.rendered.font_size == 42, "font size not passed")
assert(pager.v_scroll_bar.enable == true, "scrollbar must be enabled with multiple pages")
assert(pager.htmlbox_widget.page_number == 1, "starts on page 1")
assert(pager.v_scroll_bar.low == 0 and math.abs(pager.v_scroll_bar.high - 1 / 3) < 0.001, "scrollbar ratios wrong")

local pos = { intersectWith = function() return true end, x = 900, y = 500 }
assert(pager:onPagerTap(nil, { pos = pos }) == true, "tap right half must page forward")
assert(pager.htmlbox_widget.page_number == 2, "tap did not advance")
assert(dirty_calls > 0 and last_dirty_widget == show_parent, "repaint must target the shell")
assert(pager.htmlbox_widget.freed > 0, "page change must free the render buffer")

assert(pager:onPagerPan(nil, { pos = pos, relative = { y = -300 } }) == false, "pan should not consume")
assert(pager:onPagerPanRelease() == true, "pan release must page")
assert(pager.htmlbox_widget.page_number == 3, "pan did not advance")

assert(pager:onPagerSwipe(nil, { direction = "north" }) == false, "must not page past last page")
assert(pager:onPagerTap(nil, { pos = pos }) == false, "must not page past last page")
assert(pager:scrollToRatio(0) == true and pager.htmlbox_widget.page_number == 1, "scrollbar ratio must jump")
assert(pager:onPagerPageDown() == true and pager.htmlbox_widget.page_number == 2, "PgFwd must page")
assert(pager:onPagerPageUp() == true and pager.htmlbox_widget.page_number == 1, "PgBack must page")

PAGE_COUNT = 1
local single = Pager:new{
    width = 1200,
    height = 1400,
    body = "short",
    css = "css",
    font_size = 42,
}
assert(single.v_scroll_bar.enable == false, "single page must not show scrollbar")
assert(single:onPagerSwipe(nil, { direction = "north" }) == false, "single page must not scroll")

print("OK article pager smoke: pages=3 pan/swipe/tap/keys + single page")
