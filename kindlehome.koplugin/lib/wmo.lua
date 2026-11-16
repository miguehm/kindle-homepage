local Wmo = {}

local MAP = {
    [0] = "Clear sky",
    [1] = "Mainly clear",
    [2] = "Partly cloudy",
    [3] = "Overcast",
    [45] = "Fog",
    [48] = "Depositing rime fog",
    [51] = "Light drizzle",
    [53] = "Moderate drizzle",
    [55] = "Dense drizzle",
    [56] = "Light freezing drizzle",
    [57] = "Dense freezing drizzle",
    [61] = "Slight rain",
    [63] = "Moderate rain",
    [65] = "Heavy rain",
    [66] = "Light freezing rain",
    [67] = "Heavy freezing rain",
    [71] = "Slight snow fall",
    [73] = "Moderate snow fall",
    [75] = "Heavy snow fall",
    [77] = "Snow grains",
    [80] = "Slight rain showers",
    [81] = "Moderate rain showers",
    [82] = "Violent rain showers",
    [85] = "Slight snow showers",
    [86] = "Heavy snow showers",
    [95] = "Thunderstorm",
    [96] = "Thunderstorm with slight hail",
    [99] = "Thunderstorm with heavy hail",
}

function Wmo.to_text(code)
    if code == nil or code == "" then
        return "Unknown conditions"
    end
    local n = tonumber(code)
    if n == nil then
        return "Unknown conditions"
    end
    return MAP[n] or ("Unknown conditions (code " .. tostring(n) .. ")")
end

-- Monochrome glyph key for DESIGN.md icon assets. Codes are grouped into the
-- stable e-ink states; unknown codes get a neutral glyph instead of a blank.
function Wmo.to_icon(code)
    local n = tonumber(code)
    if n == nil then return "unknown" end
    if n == 0 or n == 1 then return "sun" end
    if n == 2 then return "partly" end
    if n == 3 then return "cloud" end
    if n == 45 or n == 48 then return "fog" end
    if (n >= 51 and n <= 67) or (n >= 80 and n <= 82) then return "rain" end
    if (n >= 71 and n <= 77) or n == 85 or n == 86 then return "snow" end
    if n >= 95 then return "storm" end
    return "unknown"
end

return Wmo
