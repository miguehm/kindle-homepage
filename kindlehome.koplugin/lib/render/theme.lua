-- UI theme tokens for Kindle Home.
--
-- Rules:
-- - HTML/CSS uses relative units only (em/%) for type, so MuPDF's
--   `default_font_size` (already DPI-scaled) governs text size. Absolute px
--   font sizes are physically tiny on a 300 ppi PaperWhite 5 and are
--   forbidden.
-- - Native widget sizes are expressed in design dp and scaled through
--   Screen:scaleBySize(), which accounts for the device screen size.
-- - One knob (`ui_font_scale`) scales both the HTML base size and the native
--   action bar, so the whole UI grows/shrinks consistently.

local Device = require("device")
local Screen = Device.screen

local Theme = {}

local MIN_SCALE = 0.85
local MAX_SCALE = 1.6
local DEFAULT_SCALE = 1.0

-- HTML base font sizes in design dp (before scaleBySize).
Theme.UI_BASE = 26
Theme.ARTICLE_BASE = 25

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

-- Dashboard HTML -----------------------------------------------------------
--
-- Cards use borders + spacing instead of gray fills: large mid-tone areas
-- ghost badly on e-ink. Everything is a block element (no flex/grid) because
-- MuPDF's HTML layout support is intentionally small.
local DASHBOARD_CSS = table.concat({
    "@page{margin:0;}",
    "body{margin:0;padding:0.8em;color:#000;background:#fff;font-family:sans-serif;line-height:1.45;}",
    ".hero{margin:0 0 0.6em 0;}",
    ".clock{font-size:2.1em;font-weight:bold;line-height:1.05;}",
    ".date{font-size:1em;margin-top:0.15em;}",
    ".status{border:0.07em solid #000;padding:0.45em 0.6em;margin:0 0 0.6em 0;font-size:0.9em;}",
    ".card{border:0.07em solid #000;padding:0.6em 0.7em;margin:0.6em 0;}",
    ".card-title{font-size:0.82em;font-weight:bold;letter-spacing:0.04em;margin:0 0 0.35em 0;}",
    ".temp{font-size:1.9em;font-weight:bold;line-height:1.1;}",
    ".cond{font-size:1.05em;}",
    ".small{font-size:0.85em;color:#222;margin-top:0.2em;}",
    ".muted{font-size:0.82em;color:#222;margin-top:0.2em;}",
    ".hint{border:0.07em solid #000;padding:0.45em 0.6em;margin:0 0 0.6em 0;font-size:0.9em;}",
    ".hn{padding:0.55em 0;border-top:0.05em solid #000;}",
    ".hn-first{border-top:0;}",
    ".hn-title{font-size:1em;font-weight:bold;}",
    ".rank{font-weight:bold;}",
    ".hn-meta{font-size:0.82em;color:#222;margin-top:0.15em;}",
    ".badge{font-size:0.8em;color:#222;}",
    "a{color:#000;text-decoration:underline;}",
    ".footer-note{font-size:0.8em;color:#222;margin-top:1em;}",
}, "")

function Theme.dashboard_css()
    return DASHBOARD_CSS
end

return Theme
