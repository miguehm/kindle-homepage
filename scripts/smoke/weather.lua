-- SPDX-License-Identifier: MIT
-- Smoke: Open-Meteo normalization for the redesigned weather panel (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

local captured_url, captured_opts

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["lib/http"] = function()
    return {
        get_json = function(url, opts)
            captured_url, captured_opts = url, opts
            return {
                ok = true,
                status = 200,
                json = {
                    current = {
                        temperature_2m = 19.4,
                        relative_humidity_2m = 54,
                        weather_code = 0,
                        wind_speed_10m = 12,
                    },
                    daily = {
                        weather_code = { 0, 61 },
                        temperature_2m_max = { 21, 18 },
                        temperature_2m_min = { 12, 11 },
                    },
                    timezone = "Europe/Madrid",
                },
            }
        end,
    }
end

local Weather = require("lib/weather")
local Wmo = require("lib/wmo")

local config = {
    get = function(_, key)
        if key == "weather_lat" then return 40.4 end
        if key == "weather_lon" then return -3.7 end
        if key == "weather_place_name" then return "Madrid" end
        if key == "http_timeout_s" then return 6 end
        if key == "http_max_bytes" then return 262144 end
        return nil
    end,
}

assert(Weather.has_location(config) == true, "location guard missing")
local res = Weather.fetch(config, {})
assert(res.ok == true, "fetch failed")
assert(captured_url:find("forecast_days=2", 1, true), "two-day forecast missing")
assert(captured_url:find("wind_speed_unit=kmh", 1, true), "km/h units missing")
assert(captured_url:find("relative_humidity_2m", 1, true), "humidity field missing")
assert(captured_url:find("wind_speed_10m", 1, true), "wind field missing")
assert(captured_opts.timeout_s == 6, "timeout not forwarded")

local p = res.payload
assert(p.current_temp == 19.4 and p.temp_max == 21 and p.temp_min == 12, "temperatures wrong")
assert(p.wind_kmh == 12 and p.humidity == 54, "wind/humidity wrong")
assert(p.tomorrow_temp_max == 18 and p.tomorrow_temp_min == 11, "tomorrow temperatures wrong")
assert(p.icon == "sun" and p.tomorrow_icon == "rain", "weather glyphs wrong")
assert(p.condition_text == "Clear sky" and p.tomorrow_condition_text == "Slight rain", "conditions wrong")

assert(Wmo.to_icon(0) == "sun" and Wmo.to_icon(1) == "sun", "clear icon wrong")
assert(Wmo.to_icon(2) == "partly" and Wmo.to_icon(3) == "cloud", "cloud icons wrong")
assert(Wmo.to_icon(45) == "fog" and Wmo.to_icon(63) == "rain", "fog/rain icons wrong")
assert(Wmo.to_icon(75) == "snow" and Wmo.to_icon(99) == "storm", "snow/storm icons wrong")
assert(Wmo.to_icon("bad") == "unknown" and Wmo.to_icon(nil) == "unknown", "unknown icon wrong")

local empty_config = { get = function() return nil end }
assert(Weather.has_location(empty_config) == false, "location guard must reject missing coords")
local no_location = Weather.fetch(empty_config, {})
assert(no_location.ok == false and no_location.error_kind == "no_location", "no-location error missing")

print("OK weather smoke: 2-day forecast, wind/humidity, glyphs and missing fields")
