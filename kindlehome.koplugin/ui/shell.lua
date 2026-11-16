-- Fullscreen shell: native title bar + native scroll body + native action bar.
--
-- Why a shell instead of a bare scroll widget:
-- - covers_fullscreen lets UIManager skip painting the reader underneath, and
--   opening/closing with a full refresh removes e-ink ghosting.
-- - The title bar keeps an always-visible exit icon and a Back chevron; the
--   action bar keeps the primary actions reachable without scrolling.
-- - Exit paths are redundant on purpose (icon, footer button, Back key,
--   swipe down on the header).

local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local ActionBar = require("ui/widget/action_bar")
local Logger = require("lib/logger")

local Screen = Device.screen

local Shell = InputContainer:extend{
    title = "Kindle Home",
    config = nil,
    actions = nil, -- list of {icon, label, callback, enabled}
    body_factory = nil, -- function(width, height) -> widget
    body = nil,
    on_close = nil,
    on_back = nil,
    on_layout_change = nil,
    fullscreen = true,
    show_title_bar = true,
    header_factory = nil, -- function(width, shell) -> custom header widget
    _closing = false,
}

function Shell:init()
    local fullscreen = self.fullscreen
    if self.config and self.config:get("ui_fullscreen") == false then
        fullscreen = false
    end
    self.covers_fullscreen = fullscreen and true or false

    self.title_bar = nil
    local header_height = 0
    if self.show_title_bar ~= false then
        if type(self.header_factory) == "function" then
            local custom = self.header_factory(Screen:getWidth(), self)
            if custom and type(custom.getSize) == "function" and type(custom.paintTo) == "function" then
                self.title_bar = custom
            else
                Logger.warn("shell", "invalid_header_factory_fallback")
                self.title_bar = nil
            end
        end
        if not self.title_bar then
            local left_icon = nil
            local left_callback = nil
            if self.on_back then
                left_icon = "chevron.left"
                left_callback = function() self:request_back() end
            end
            self.title_bar = TitleBar:new{
                title = self.title or "",
                align = "left",
                width = Screen:getWidth(),
                fullscreen = fullscreen,
                with_bottom_line = true,
                left_icon = left_icon,
                left_icon_tap_callback = left_callback or function() end,
                close_callback = function() self:request_close() end,
                show_parent = self,
            }
        end
        self.title_bar.show_parent = self
        header_height = self.title_bar:getSize().h
    end

    self.action_bar = nil
    local footer_height = 0
    if self.actions and #self.actions > 0 then
        self.action_bar = ActionBar:new{
            buttons = self.actions,
            config = self.config,
            show_parent = self,
        }
        footer_height = self.action_bar:getSize().h
    end

    local body_height = Screen:getHeight() - header_height - footer_height
    if body_height < 1 then body_height = 1 end
    self.body = self.body_factory and self.body_factory(Screen:getWidth(), body_height, self) or nil
    if not self.body then
        Logger.err("shell", "body_missing")
    else
        self.body.dialog = self
        self.body.show_parent = self
        if self.body.htmlbox_widget then
            self.body.htmlbox_widget.dialog = self
        end
        if type(self.body.getCropRegion) == "function" then
            self.cropping_widget = self.body
        end
    end

    Logger.info("shell", "layout", {
        screen_w = Screen:getWidth(),
        screen_h = Screen:getHeight(),
        header = header_height,
        footer = footer_height,
        body_h = body_height,
        fullscreen = fullscreen,
    })

    local group = VerticalGroup:new{ align = "left" }
    if self.title_bar then table.insert(group, self.title_bar) end
    if self.body then table.insert(group, self.body) end
    if self.action_bar then table.insert(group, self.action_bar) end

    self[1] = group
    self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
    self.header_height = header_height

    self.ges_events = {
        SwipeHeader = {
            GestureRange:new{
                ges = "swipe",
                range = function()
                    return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = self.header_height }
                end,
            },
        },
    }
end

-- The native TitleBar is a transparent OverlapGroup and covers_fullscreen
-- makes UIManager skip repainting the previous screen. Without an opaque
-- fill, stale pixels from the screen underneath show through the header.
function Shell:paintTo(bb, x, y)
    local w = self.dimen and self.dimen.w or Screen:getWidth()
    local h = self.dimen and self.dimen.h or Screen:getHeight()
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    InputContainer.paintTo(self, bb, x, y)
end

function Shell:show()
    UIManager:show(self)
    UIManager:setDirty(self, "full")
    Logger.info("shell", "shown", { fullscreen = self.covers_fullscreen })
end

function Shell:request_close()
    if self._closing then return true end
    self._closing = true
    UIManager:close(self, "full")
    UIManager:setDirty(nil, "full")
    if type(self.on_close) == "function" then
        self.on_close()
    end
    Logger.info("shell", "closed")
    return true
end

function Shell:request_back()
    if type(self.on_back) == "function" then
        self.on_back()
        return true
    end
    return self:request_close()
end

function Shell:onBack()
    return self:request_back()
end

function Shell:onSwipeHeader(arg, ges)
    if ges and ges.direction == "south" then
        return self:request_close()
    end
    return false
end

function Shell:onSetRotationMode()
    if type(self.on_layout_change) ~= "function" then return false end
    local callback = self.on_layout_change
    -- Rebuild outside the event dispatch: the callback closes/recreates this
    -- widget, which must not happen while it is still handling the event.
    if UIManager.tickAfterNext then
        UIManager:tickAfterNext(callback)
    else
        callback()
    end
    return true
end

function Shell:onScreenResize()
    return self:onSetRotationMode()
end

function Shell:onCloseWidget()
    if not self._closing then
        self._closing = true
        UIManager:setDirty(nil, "full")
        if type(self.on_close) == "function" then
            self.on_close()
        end
    end
end

return Shell
