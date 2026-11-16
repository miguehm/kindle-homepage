local Http = require("lib/http")
local Logger = require("lib/logger")
local Wmo = require("lib/wmo")

local Weather = {}

local function to_num(v)
    local n = tonumber(v)
    return n
end

local function normalize(config, api_json, fetched_at)
    api_json = api_json or {}
    local current = api_json.current or {}
    local daily = api_json.daily or {}
    local function daily_at(key, index)
        local t = daily[key]
        if type(t) == "table" then return t[index] end
        return nil
    end
    local function daily0(key) return daily_at(key, 1) end

    local current_code = to_num(current.weather_code)
    local daily_code = to_num(daily0("weather_code"))
    local code = current_code ~= nil and current_code or daily_code
    local tomorrow_code = to_num(daily_at("weather_code", 2))
    local place_name = config and config:get("weather_place_name") or ""
    if type(place_name) ~= "string" then place_name = "" end

    local view = {
        place_name = place_name,
        lat = config and config:get("weather_lat") or nil,
        lon = config and config:get("weather_lon") or nil,
        current_temp = to_num(current.temperature_2m),
        temp_max = to_num(daily0("temperature_2m_max")),
        temp_min = to_num(daily0("temperature_2m_min")),
        wind_kmh = to_num(current.wind_speed_10m),
        humidity = to_num(current.relative_humidity_2m),
        tomorrow_temp_max = to_num(daily_at("temperature_2m_max", 2)),
        tomorrow_temp_min = to_num(daily_at("temperature_2m_min", 2)),
        tomorrow_wmo_code = tomorrow_code,
        tomorrow_condition_text = tomorrow_code and Wmo.to_text(tomorrow_code) or nil,
        icon = Wmo.to_icon(code),
        tomorrow_icon = Wmo.to_icon(tomorrow_code),
        wmo_code = code,
        condition_text = Wmo.to_text(code),
        observed_at = current.time or api_json.current_units and nil or nil,
        fetched_at = fetched_at or os.time(),
        timezone = api_json.timezone,
    }
    -- prefer daily code for summary if current missing
    if current_code == nil and daily_code ~= nil then
        view.condition_text = Wmo.to_text(daily_code)
        view.icon = Wmo.to_icon(daily_code)
    end
    return view
end

function Weather.has_location(config)
    if not config then return false end
    local lat = config:get("weather_lat")
    local lon = config:get("weather_lon")
    return type(lat) == "number" and type(lon) == "number"
end

function Weather.fetch(config, opts)
    opts = opts or {}
    if not Weather.has_location(config) then
        return { ok = false, error_kind = "no_location", error = "weather_location_not_configured" }
    end
    local lat = config:get("weather_lat")
    local lon = config:get("weather_lon")
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,temperature_2m_min,weather_code&wind_speed_unit=kmh&timezone=auto&forecast_days=2",
        tostring(lat), tostring(lon)
    )
    local timeout_s = opts.timeout_s or (config and config:get("http_timeout_s")) or 10
    local max_bytes = opts.max_bytes or (config and config:get("http_max_bytes")) or 131072
    local cfg_max = tonumber(max_bytes) or 131072
    if cfg_max < 16384 then cfg_max = 16384 end
    if cfg_max > 1048576 then cfg_max = 1048576 end
    local res = Http.get_json(url, {
        timeout_s = timeout_s,
        max_bytes = cfg_max,
        retries = 1,
    })
    if not res.ok then
        Logger.warn("weather", "fetch_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    local payload = normalize(config, res.json or {}, os.time())
    Logger.info("weather", "fetch_ok", { place = payload.place_name, code = payload.wmo_code })
    return {
        ok = true,
        status = res.status,
        payload = payload,
        fetched_at = payload.fetched_at,
    }
end

return Weather
