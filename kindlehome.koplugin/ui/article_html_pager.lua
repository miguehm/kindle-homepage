-- SPDX-License-Identifier: MIT
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local HtmlBoxWidget = require("ui/widget/htmlboxwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalScrollBar = require("ui/widget/verticalscrollbar")

local Input = Device.input
local Screen = Device.screen

local ArticleHtmlPager = InputContainer:extend{
    width = 0,
    height = 0,
    body = nil,
    css = nil,
    font_size = nil,
    on_link = nil,
    start_page = nil,      -- page to restore (session memory per article)
    on_page_change = nil,  -- function(page)
    htmlbox_widget = nil,
    v_scroll_bar = nil,
    _pan_y = nil,
}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function ArticleHtmlPager:init()
    local bar_w = Screen:scaleBySize(6)
    local span_w = Screen:scaleBySize(12)
    local html_w = math.max(1, self.width - bar_w - span_w)

    self.htmlbox_widget = HtmlBoxWidget:new{
        dimen = Geom:new{ w = html_w, h = self.height },
        html_link_tapped_callback = self.on_link,
    }
    self.htmlbox_widget:setContent(self.body, self.css, self.font_size)
    local start = tonumber(self.start_page)
    local count = self.htmlbox_widget.page_count or 1
    if start and start > 1 and start <= count then
        self.htmlbox_widget:setPageNumber(start)
    end

    self.v_scroll_bar = VerticalScrollBar:new{
        enable = self.htmlbox_widget.page_count > 1,
        width = bar_w,
        height = self.height,
        scroll_callback = function(ratio) self:scrollToRatio(ratio) end,
    }

    self[1] = HorizontalGroup:new{
        self.htmlbox_widget,
        HorizontalSpan:new{ width = span_w },
        self.v_scroll_bar,
    }
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self:_updateScrollBar()

    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        self.ges_events = {
            PagerSwipe = { GestureRange:new{ ges = "swipe", range = range } },
            PagerTap = { GestureRange:new{ ges = "tap", range = range } },
            PagerPan = { GestureRange:new{ ges = "pan", range = range } },
            PagerPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
        }
    end
    if Device:hasKeys() and Input and Input.group then
        self.key_events = {
            PagerPageUp = { { Input.group.PgBack } },
            PagerPageDown = { { Input.group.PgFwd } },
        }
    end
end

function ArticleHtmlPager:_updateScrollBar()
    local count = self.htmlbox_widget.page_count
    if not self.v_scroll_bar or not count or count < 1 then return end
    local page = self.htmlbox_widget.page_number
    self.v_scroll_bar:set((page - 1) / count, page / count)
end

function ArticleHtmlPager:_repaint()
    self.htmlbox_widget:freeBb()
    self:_updateScrollBar()
    UIManager:setDirty(self.show_parent or self, function()
        return "ui", self.dimen
    end)
end

function ArticleHtmlPager:scrollText(direction)
    local htmlbox = self.htmlbox_widget
    if not htmlbox or direction == 0 then return false end
    local target = htmlbox.page_number + direction
    if target < 1 or target > htmlbox.page_count then return false end
    htmlbox:setPageNumber(target)
    self:_repaint()
    if type(self.on_page_change) == "function" then self.on_page_change(target) end
    return true
end

function ArticleHtmlPager:scrollToRatio(ratio)
    local htmlbox = self.htmlbox_widget
    if not htmlbox or not htmlbox.page_count or htmlbox.page_count < 1 then return false end
    local page = 1 + math.floor(htmlbox.page_count * clamp(ratio, 0, 1))
    page = clamp(page, 1, htmlbox.page_count)
    if page == htmlbox.page_number then return false end
    htmlbox:setPageNumber(page)
    self:_repaint()
    if type(self.on_page_change) == "function" then self.on_page_change(page) end
    return true
end

function ArticleHtmlPager:onPagerSwipe(_, ges)
    if ges.direction == "north" then
        return self:scrollText(1)
    elseif ges.direction == "south" then
        return self:scrollText(-1)
    end
    return false
end

-- Taps on links never reach this handler: HtmlBoxWidget (a child) follows
-- them first through html_link_tapped_callback. Other taps turn the page:
-- the left third goes back, the right two thirds go forward.
function ArticleHtmlPager:onPagerTap(_, ges)
    if not ges.pos then return false end
    if ges.pos.x < Screen:getWidth() / 3 then
        return self:scrollText(-1)
    end
    return self:scrollText(1)
end

function ArticleHtmlPager:onPagerPan(_, ges)
    if not ges.pos or not ges.pos:intersectWith(self.dimen) then return false end
    self._pan_y = ges.relative and ges.relative.y or 0
    return false
end

function ArticleHtmlPager:onPagerPanRelease()
    if not self._pan_y then return false end
    local dy = self._pan_y
    self._pan_y = nil
    local threshold = math.max(20, math.floor(self.height * 0.15))
    if dy <= -threshold then return self:scrollText(1) end
    if dy >= threshold then return self:scrollText(-1) end
    return false
end

function ArticleHtmlPager:onPagerPageUp()
    return self:scrollText(-1)
end

function ArticleHtmlPager:onPagerPageDown()
    return self:scrollText(1)
end

return ArticleHtmlPager
