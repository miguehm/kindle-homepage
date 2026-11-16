local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Config = {}
Config.__index = Config

local DEFAULTS = {
    -- General/UI
    refresh_on_open = false, -- MVP: no automatic network fetch on open
    show_battery = true,
    show_network = true,
    show_weather = true,
    show_hn = true,
    ui_font_scale = 1.0, -- 0.85 .. 1.6 (small .. extra large)
    ui_fullscreen = true,
    ui_show_test_article = false, -- dev/debug entry in the dashboard
    ui_force_article_fallback = false, -- dev/debug: skip ReaderUI to exercise the pager
    -- Rutas
    storage_mode = "documents", -- "documents" | "datadir"
    documents_subdir = "KindleHome",
    custom_content_dir = "", -- absolute custom content root; empty = use storage_mode/subdir
    -- Clima
    weather_enabled = true,
    weather_lat = nil,
    weather_lon = nil,
    weather_place_name = "",
    weather_ttl_minutes = 60,
    -- HN/hnmd
    hnmd_enabled = true,
    hnmd_base_url = "https://hnmd.miguehm.com/v1",
    hnmd_api_key = "",
    hnmd_max_items = 10,
    hnmd_ttl_minutes = 30,
    index_max_bytes = 131072,   -- 128 KiB: /top metadatos (sin cuerpos)
    article_max_bytes = 524288, -- 512 KiB por artículo .md descargado
    -- Red
    http_timeout_s = 6,
    http_max_bytes = 262144, -- 256 KiB (Kindle has little free RAM)
    refresh_budget_s = 20,
}

-- Keys whose default is intentionally nil: they must still be settable and
-- reloadable (otherwise Config:set rejects them and the weather location is
-- never persisted).
local OPTIONAL_KEYS = {
    weather_lat = true,
    weather_lon = true,
}

local function is_number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp_int(v, minv, maxv, default)
    if not is_number(v) then return default end
    v = math.floor(v)
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function clamp_number(v, minv, maxv, default)
    if not is_number(v) then return default end
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function as_bool(v, default)
    if type(v) == "boolean" then return v end
    return default
end

local function as_string(v, default)
    if type(v) == "string" then return v end
    return default
end

-- hnmd API paths are versioned (/v1/top). A bare host (legacy config or a
-- custom server) is normalized to the current version so stored settings from
-- older installs keep working without manual edits.
local function sanitize_base_url(v, default)
    if type(v) ~= "string" then return default end
    v = v:match("^%s*(.-)%s*$") or ""
    if v == "" then return default end
    if not v:match("^https://") then
        if v:match("^http://") then
            v = "https://" .. v:sub(8)
        else
            return default
        end
    end
    v = v:gsub("/+$", "")
    local rest = v:match("^https://(.+)$")
    if not rest or rest == "" then return default end
    if not rest:find("/", 1, true) then
        v = v .. "/v1"
    end
    return v
end

local function sanitize_coord(v, minv, maxv)
    if v == nil or v == "" then return nil end
    if type(v) == "string" then v = tonumber(v) end
    if not is_number(v) then return nil end
    if v < minv or v > maxv then return nil end
    return v
end

-- Only absolute, normalized paths are accepted; ".." and KOReader's own
-- install directory are rejected so a typo cannot write outside user storage.
-- An empty value disables the override and restores the legacy path settings.
local function sanitize_custom_dir(v, default)
    if type(v) ~= "string" then return default end
    local s = v:match("^%s*(.-)%s*$") or ""
    if s == "" then return "" end
    if s:sub(1, 1) ~= "/" or s:find("[%z%c]") then return default end
    for segment in s:gmatch("[^/]+") do
        if segment == ".." or segment == "." then return default end
    end
    s = s:gsub("/+", "/")
    if s ~= "/" then s = s:gsub("/+$", "") end
    if #s > 255 then return default end
    if s == "/mnt/us/koreader" or s:match("^/mnt/us/koreader/") then return default end
    return s
end

local function sanitize(key, value, default)
    if key == "refresh_on_open" or key == "show_battery" or key == "show_network"
        or key == "show_weather" or key == "show_hn"
        or key == "weather_enabled" or key == "hnmd_enabled"
         or key == "ui_fullscreen" or key == "ui_show_test_article"
         or key == "ui_force_article_fallback" then
        return as_bool(value, default)
    elseif key == "ui_font_scale" then
        return clamp_number(value, 0.85, 1.6, default)
    elseif key == "storage_mode" then
        if value == "documents" or value == "datadir" then return value end
        return default
    elseif key == "documents_subdir" then
        local s = as_string(value, default)
        s = s:gsub("[/\\]", ""):match("^%s*(.-)%s*$") or default
        if s == "" or s == ".." or s == "." then s = default end
        return s
    elseif key == "custom_content_dir" then
        return sanitize_custom_dir(value, default)
    elseif key == "weather_lat" then
        return sanitize_coord(value, -90, 90)
    elseif key == "weather_lon" then
        return sanitize_coord(value, -180, 180)
    elseif key == "weather_place_name" or key == "hnmd_api_key" then
        return as_string(value, default)
    elseif key == "hnmd_base_url" then
        return sanitize_base_url(value, default)
    elseif key == "hnmd_max_items" then
        return clamp_int(value, 1, 20, default)
    elseif key == "weather_ttl_minutes" or key == "hnmd_ttl_minutes" then
        return clamp_int(value, 1, 10080, default) -- up to 7 days
    elseif key == "http_timeout_s" then
        return clamp_int(value, 1, 60, default)
    elseif key == "index_max_bytes" then
        return clamp_int(value, 32768, 262144, default) -- 32 .. 256 KiB
    elseif key == "article_max_bytes" then
        return clamp_int(value, 16384, 1048576, default) -- 16 KiB .. 1 MiB
    elseif key == "http_max_bytes" then
        return clamp_int(value, 16384, 10485760, default) -- 16 KiB .. 10 MiB
    elseif key == "refresh_budget_s" then
        return clamp_int(value, 1, 120, default)
    end
    return value == nil and default or value
end

function Config:new()
    local o = setmetatable({}, self)
    o.settings_path = DataStorage:getSettingsDir() .. "/kindlehome.lua"
    o.settings = LuaSettings:open(o.settings_path)
    o.values = {}
    o:load()
    return o
end

function Config:load()
    for k, default in pairs(DEFAULTS) do
        local stored = self.settings:readSetting(k)
        if stored == nil then
            self.values[k] = default
        else
            self.values[k] = sanitize(k, stored, default)
        end
    end
    for k in pairs(OPTIONAL_KEYS) do
        local stored = self.settings:readSetting(k)
        if stored ~= nil then
            self.values[k] = sanitize(k, stored, DEFAULTS[k])
        end
    end
    return self
end

function Config:get(key)
    local v = self.values[key]
    if v ~= nil then return v end
    local d = DEFAULTS[key]
    if type(d) == "table" then
        local copy = {}
        for i, item in ipairs(d) do copy[i] = item end
        return copy
    end
    return d
end

function Config:defaults()
    return DEFAULTS
end

function Config:set(key, value)
    if DEFAULTS[key] == nil and not OPTIONAL_KEYS[key] then
        return false
    end
    local sanitized = sanitize(key, value, DEFAULTS[key])
    self.values[key] = sanitized
    self.settings:saveSetting(key, sanitized)
    return true
end

-- Single source of truth for the menu: rejects input that the sanitizer would
-- silently fall back to the default, so the user gets an actionable message.
function Config:validate_custom_dir(value)
    local trimmed = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
    if trimmed == "" then return true end
    return sanitize_custom_dir(value, "") ~= ""
end

function Config:flush()
    if self.settings and self.settings.flush then
        self.settings:flush()
    end
end

function Config:get_ttl_seconds(prefix)
    local minutes = self:get(prefix .. "_ttl_minutes")
    if not is_number(minutes) then minutes = 60 end
    return math.floor(minutes) * 60
end

return Config
