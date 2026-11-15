local Cache = require("lib/cache")
local Logger = require("lib/logger")
local Refresh = require("lib/refresh")
local Weather = require("lib/weather")

local WeatherState = {}

local function fmt_temp(v)
    if type(v) ~= "number" then return nil end
    local n = math.floor(v + 0.5)
    return tostring(n) .. "°C"
end

local function build_line(payload, is_stale, err_kind)
    payload = payload or {}
    local place = payload.place_name
    if type(place) ~= "string" or place == "" then
        if type(payload.lat) == "number" and type(payload.lon) == "number" then
            place = string.format("%.4f, %.4f", payload.lat, payload.lon)
        else
            place = "Unknown location"
        end
    end
    local parts = {}
    local cur = fmt_temp(payload.current_temp)
    local cond = payload.condition_text or "Unknown conditions"
    if cur then
        table.insert(parts, cur .. " " .. cond)
    else
        table.insert(parts, cond)
    end
    local hi = fmt_temp(payload.temp_max)
    local lo = fmt_temp(payload.temp_min)
    if hi or lo then
        table.insert(parts, string.format("H:%s L:%s", hi or "n/a", lo or "n/a"))
    end
    local line = place .. " — " .. table.concat(parts, ", ")
    if is_stale then
        line = line .. " (stale)"
    end
    if err_kind and err_kind ~= "" and err_kind ~= "ok" then
        line = line .. " [" .. tostring(err_kind) .. "]"
    end
    return line
end

function WeatherState.load(config, paths, opts)
    opts = opts or {}
    local enabled = config and config:get("weather_enabled")
    if not enabled then
        return { status = "disabled", line = "Weather: disabled", payload = nil }
    end
    if not Weather.has_location(config) then
        return {
            status = "configure_location",
            line = "Weather: configure location in settings (lat/lon or place).",
            payload = nil,
            needs_location = true,
        }
    end

    local cache = Cache:new(paths)
    local ttl_seconds = math.max(60, (tonumber(config:get("weather_ttl_minutes")) or 60) * 60)
    local budget = opts.budget
    local res = Refresh.load_source(cache, {
        name = "weather.json",
        ttl_seconds = ttl_seconds,
        source = "open-meteo",
        allow_network = opts.allow_network ~= false,
        budget = budget,
        fetch_fn = function()
            return Weather.fetch(config, {
                timeout_s = config:get("http_timeout_s"),
                max_bytes = config:get("http_max_bytes"),
            })
        end,
    })

    local env = res.envelope
    local payload = env and env.payload or nil
    local is_stale = res.stale or (env and env.status == "stale") or false
    local err_kind = res.error_kind or (env and env.error and env.error.kind) or nil

    if payload and type(payload) == "table" then
        local line = build_line(payload, is_stale, (is_stale and err_kind) or nil)
        local status = "ok"
        if is_stale then status = "stale" end
        return {
            status = status,
            line = line,
            payload = payload,
            fetched_at = env and env.fetched_at or payload.fetched_at,
            stale = is_stale,
            error_kind = err_kind,
            from_cache = res.from_cache,
        }
    end

    local msg = "Weather: unavailable."
    if err_kind == "offline" or err_kind == "timeout" or err_kind == "network" then
        msg = "Weather: offline or network error. Turn on WiFi and refresh."
    elseif err_kind == "http_other" or err_kind == "http_503" then
        msg = "Weather: service unavailable. Try again later."
    elseif err_kind == "parse" or err_kind == "too_large" then
        msg = "Weather: data error. Try refreshing."
    elseif err_kind == "budget_exceeded" then
        msg = "Weather: refresh budget exceeded."
    end
    Logger.warn("weather_state", "unavailable", { kind = err_kind })
    return { status = "error", line = msg, payload = nil, error_kind = err_kind }
end

return WeatherState
