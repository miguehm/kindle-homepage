local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Config = {}
Config.__index = Config

local DEFAULTS = {
    -- General/UI
    refresh_on_open = true,
    show_battery = true,
    show_network = true,
    -- Rutas
    storage_mode = "documents", -- "documents" | "datadir"
    documents_subdir = "KindleHome",
    -- Clima
    weather_enabled = true,
    weather_lat = nil,
    weather_lon = nil,
    weather_place_name = "",
    weather_ttl_minutes = 60,
    -- HN/hnmd
    hnmd_enabled = true,
    hnmd_base_url = "https://hnmd.miguehm.com",
    hnmd_api_key = "",
    hnmd_max_items = 10,
    hnmd_ttl_minutes = 30,
    -- RSS
    rss_enabled = true,
    rss_ttl_minutes = 60,
    rss_feeds = {},
    -- Red
    http_timeout_s = 10,
    http_max_bytes = 524288, -- 512 KiB
    refresh_budget_s = 20,
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

local function as_bool(v, default)
    if type(v) == "boolean" then return v end
    return default
end

local function as_string(v, default)
    if type(v) == "string" then return v end
    return default
end

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
    return v
end

local function sanitize_coord(v, minv, maxv)
    if v == nil or v == "" then return nil end
    if type(v) == "string" then v = tonumber(v) end
    if not is_number(v) then return nil end
    if v < minv or v > maxv then return nil end
    return v
end

local function sanitize_feeds(v)
    if type(v) ~= "table" then return {} end
    local out = {}
    local n = 0
    for _, feed in ipairs(v) do
        if type(feed) == "table" then
            n = n + 1
            local id = as_string(feed.id, "")
            if id == "" then id = "feed_" .. tostring(n) end
            table.insert(out, {
                id = id,
                name = as_string(feed.name, ""),
                url = as_string(feed.url, ""),
                enabled = as_bool(feed.enabled, true),
                max_items = clamp_int(feed.max_items, 1, 100, 20),
                max_age_hours = (is_number(feed.max_age_hours) and math.floor(feed.max_age_hours)) or feed.max_age_hours,
            })
        end
    end
    return out
end

local function sanitize(key, value, default)
    if key == "refresh_on_open" or key == "show_battery" or key == "show_network"
        or key == "weather_enabled" or key == "hnmd_enabled" or key == "rss_enabled" then
        return as_bool(value, default)
    elseif key == "storage_mode" then
        if value == "documents" or value == "datadir" then return value end
        return default
    elseif key == "documents_subdir" then
        local s = as_string(value, default)
        s = s:gsub("[/\\]", ""):match("^%s*(.-)%s*$") or default
        if s == "" then s = default end
        return s
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
    elseif key == "weather_ttl_minutes" or key == "hnmd_ttl_minutes" or key == "rss_ttl_minutes" then
        return clamp_int(value, 1, 10080, default) -- up to 7 days
    elseif key == "http_timeout_s" then
        return clamp_int(value, 1, 60, default)
    elseif key == "http_max_bytes" then
        return clamp_int(value, 16384, 10485760, default) -- 16 KiB .. 10 MiB
    elseif key == "refresh_budget_s" then
        return clamp_int(value, 1, 120, default)
    elseif key == "rss_feeds" then
        return sanitize_feeds(value)
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
    return self
end

function Config:get(key)
    local v = self.values[key]
    if v ~= nil then return v end
    local d = DEFAULTS[key]
    if type(d) == "table" then
        -- return a shallow copy for mutable defaults (feeds)
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
    if DEFAULTS[key] == nil then
        return false
    end
    local sanitized = sanitize(key, value, DEFAULTS[key])
    self.values[key] = sanitized
    self.settings:saveSetting(key, sanitized)
    return true
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

