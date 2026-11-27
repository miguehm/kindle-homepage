-- SPDX-License-Identifier: MIT
-- UI theme tokens for Kindle Home.
--
-- Rules:
-- - HTML/CSS uses relative units only (em/%) for type, so MuPDF's
--   `default_font_size` (already DPI-scaled) governs text size. Absolute px
--   font sizes are physically tiny on high-DPI e-ink screens and are
--   forbidden.
-- - Native widget sizes are expressed in design dp and scaled through
--   Screen:scaleBySize(), which accounts for the device screen size.
-- - One knob (`ui_font_scale`) scales both the HTML base size and the native
--   action bar, so the whole UI grows/shrinks consistently.

local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = Device.screen

local Theme = {}

local MIN_SCALE = 0.85
local MAX_SCALE = 1.6
local DEFAULT_SCALE = 1.0

-- HTML base font sizes in design dp (before scaleBySize).
Theme.UI_BASE = 26
Theme.ARTICLE_BASE = 25

-- Monochrome design tokens, translated to the discrete 8-bit grays available
-- on electrophoretic displays. No alpha/dithering/tints.
Theme.color = {
    canvas = Blitbuffer.COLOR_WHITE,
    fg = Blitbuffer.COLOR_BLACK,
    muted = Blitbuffer.COLOR_GRAY_6,       -- #666666 secondary metadata
    -- #E5E5E5 is not one of the 16 discrete e-ink levels (0x00, 0x11 … 0xFF);
    -- an off-level gray gets dithered, so the nearest level is used instead.
    hairline = Blitbuffer.COLOR_GRAY_E,    -- #EEEEEE (nearest discrete #E5E5E5)
    inverse_bg = Blitbuffer.COLOR_BLACK,
    inverse_fg = Blitbuffer.COLOR_WHITE,
}

-- Type scale in design dp (multiplied by ui_font_scale). Serif for display and
-- body, sans for labels/system chrome.
Theme.type = {
    display = 32,
    headline_lg = 26,
    headline_md = 20,
    headline_sm = 18,
    body_lg = 17,
    body_md = 15,
    body_sm = 13,
    label_lg = 14,
    label_md = 12,
    label_sm = 10,
}

-- Extra leading (TextBoxWidget `line_height`, in em) per role. DESIGN.md asks
-- for deliberately tall body lines; headlines and labels keep KOReader's 0.3.
Theme.line_height = {
    body_lg = 0.5,
    body_md = 0.45,
    body_sm = 0.4,
}

-- Spacing on the 4dp sub-grid.
Theme.space = {
    xs = 4,
    sm = 8,
    md = 12,
    gutter = 16,
    margin = 20,
    lg = 24,
    xl = 36,
}

-- Noto Serif/Noto Sans ship with KOReader and provide serif/sans faces without
-- adding weight to the plugin or requiring user fonts.
Theme.faces = {
    serif = "NotoSerif-Regular.ttf",
    serif_bold = "NotoSerif-Bold.ttf",
    sans = "NotoSans-Regular.ttf",
    sans_bold = "NotoSans-Bold.ttf",
}

-- Component sizes in design dp. Widgets read these instead of literals so the
-- whole UI stays on the 4dp grid and scales with ui_font_scale.
Theme.size = {
    header_h = 52,      -- dashboard/TODO'S header band
    nav_h = 52,         -- bottom navigation cells
    icon = 24,          -- standard glyph
    icon_sm = 20,       -- in-row glyphs
    icon_lg = 32,       -- hero weather glyph
    hit_min = 48,       -- minimum touch target (both axes)
    card_pad = 12,      -- card inner padding
    badge_pad = 4,      -- inverted badge padding
    chip_pad = 8,       -- chip horizontal padding
    rank_col = 32,      -- story rank column
    section_gap = 8,    -- vertical gap between body sections
    battery_w = 28,
    battery_h = 12,
    check = 16,         -- checkbox square
    check_fill = 10,    -- checked inner square
    action_h = 56,      -- article fallback action bar
}

Theme.STORY_PAGE_SIZE = 4

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Theme.normalize_scale(value)
    local v = tonumber(value)
    if not v or v ~= v then return DEFAULT_SCALE end
    return clamp(v, MIN_SCALE, MAX_SCALE)
end

function Theme.scale(config)
    if config and type(config.get) == "function" then
        local ok, value = pcall(function() return config:get("ui_font_scale") end)
        if ok then return Theme.normalize_scale(value) end
    end
    return DEFAULT_SCALE
end

-- Scaled pixel size for HTML `default_font_size` and CSS-free layout values.
function Theme.font_size(config, base_dp)
    return Screen:scaleBySize((tonumber(base_dp) or Theme.UI_BASE) * Theme.scale(config))
end

-- Scaled pixel size for native widgets (heights, icons, paddings).
function Theme.native_size(config, dp)
    return Screen:scaleBySize((tonumber(dp) or 1) * Theme.scale(config))
end

-- Unscaled size for Font:getFace(), which applies scaleBySize() itself.
function Theme.native_font_size(config, dp)
    return (tonumber(dp) or 18) * Theme.scale(config)
end

function Theme.scale_label(value)
    local v = Theme.normalize_scale(value)
    if v <= 0.95 then return "Small" end
    if v <= 1.1 then return "Medium" end
    if v <= 1.3 then return "Large" end
    return "Extra large"
end

-- One physical pixel at the design grid, rounded up so it survives scaling.
function Theme.hairline(config)
    return math.max(1, Theme.native_size(config, 1))
end

function Theme.px(config, name)
    return Theme.native_size(config, Theme.size[name])
end

-- Touch targets never shrink below 48dp, even at the smallest text scale.
function Theme.hit_size(config)
    return math.max(Theme.native_size(config, Theme.size.hit_min),
        Theme.native_size(nil, Theme.size.hit_min))
end

function Theme.margin(config)
    return Theme.native_size(config, Theme.space.margin)
end

-- Face for a design type role. Falls back to the user's content font if a
-- KOReader build does not bundle Noto Serif/Sans.
function Theme.face(config, role, bold)
    local Font = require("ui/font")
    local dp = Theme.type[role] or Theme.type.body_md
    local size = Theme.native_font_size(config, dp)
    local label = role and role:sub(1, 5) == "label"
    local name = label
        and ((bold and Theme.faces.sans_bold) or Theme.faces.sans)
        or ((bold and Theme.faces.serif_bold) or Theme.faces.serif)
    local ok, face = pcall(function() return Font:getFace(name, size) end)
    if ok and face then return face end
    local fallback_ok, fallback = pcall(function() return Font:getFace("cfont", size) end)
    if fallback_ok and fallback then return fallback end
    return nil
end

-- Icon file for a dashboard glyph. plugin_dir is supplied by main.lua
-- (the plugin's own directory); without it the widget degrades to text only.
function Theme.icon_file(plugin_dir, group, name, inverse)
    if type(plugin_dir) ~= "string" or plugin_dir == "" then return nil end
    local suffix = inverse and "-inverse" or ""
    return plugin_dir .. "/assets/icons/" .. group .. "/" .. name .. suffix .. ".svg"
end

return Theme
