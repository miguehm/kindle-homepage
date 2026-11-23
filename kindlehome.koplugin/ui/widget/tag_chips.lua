-- SPDX-License-Identifier: MIT
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local Theme = require("lib/render/theme")
local DesignText = require("ui/widget/design_text")

local TagChips = {}

local TapChip = InputContainer:extend{
    text = nil,
    config = nil,
    fgcolor = nil,
    on_tap = nil,
    on_hold = nil,
    show_parent = nil,
}

function TapChip:init()
    self.show_parent = self.show_parent or self
    self[1] = DesignText.line(self.text or "", self.config, "label_sm", true, self.fgcolor)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapChip = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldChip = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function TapChip:onTapChip()
    UIManager:setDirty(self.show_parent, "ui")
    if type(self.on_tap) == "function" then self.on_tap() end
    return true
end

function TapChip:onHoldChip()
    if type(self.on_hold) ~= "function" then return false end
    self.on_hold()
    return true
end

local function chip_frame(chip, config, callbacks, show_parent)
    local fgcolor = chip.active and Theme.color.inverse_fg or Theme.color.fg
    local on_tap
    local on_hold = nil
    if chip.kind == "status" then
        on_tap = function() callbacks.on_status(chip.value) end
    else
        on_tap = function() callbacks.on_tag(chip.tag) end
        if chip.can_open then
            -- A long press opens the tag's Markdown; the chip itself only filters.
            on_hold = function() callbacks.on_tag_doc(chip.tag) end
        end
    end
    local label = TapChip:new{
        text = chip.label .. ": " .. tostring(chip.count),
        config = config,
        fgcolor = fgcolor,
        show_parent = show_parent,
        on_tap = on_tap,
        on_hold = on_hold,
    }
    local group = HorizontalGroup:new{ align = "center" }
    table.insert(group, label)
    local border = Theme.hairline(config)
    local padding = Theme.native_size(config, 5)
    local width = label:getSize().w + 2 * (border + padding)
    return FrameContainer:new{
        margin = 0,
        padding = padding,
        bordersize = border,
        color = Theme.color.hairline,
        background = chip.active and Theme.color.inverse_bg or Theme.color.canvas,
        group,
    }, width
end

local function layout(chips, config, content_w, callbacks)
    if #chips == 0 then return nil end
    local show_parent = callbacks.show_parent
    local gap = Theme.native_size(config, Theme.space.xs)
    local root = VerticalGroup:new{ align = "left" }
    local row = HorizontalGroup:new{ align = "center" }
    local used = 0
    local row_count = 0

    for _, chip in ipairs(chips) do
        local frame, width = chip_frame(chip, config, callbacks, show_parent)
        if used > 0 and used + width > content_w then
            if row_count > 0 then
                table.insert(root, DesignText.span(config, Theme.space.xs))
            end
            table.insert(root, row)
            row_count = row_count + 1
            row = HorizontalGroup:new{ align = "center" }
            used = 0
        end
        if used > 0 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, frame)
        used = used + width + gap
    end
    if row_count > 0 then table.insert(root, DesignText.span(config, Theme.space.xs)) end
    table.insert(root, row)
    return root
end

function TagChips.build(model, config, content_w, callbacks)
    return layout(model and model.tags or {}, config, content_w, callbacks)
end

function TagChips.build_status(model, config, content_w, callbacks)
    return layout(model and model.status_chips or {}, config, content_w, callbacks)
end

return TagChips
