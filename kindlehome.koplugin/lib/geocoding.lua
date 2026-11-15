local Http = require("lib/http")
local Logger = require("lib/logger")

local Geocoding = {}

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function urlencode(s)
    s = tostring(s or "")
    s = s:gsub("\n", "\r\n")
    s = s:gsub("([^%w%-%._~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    s = s:gsub(" ", "%%20")
    return s
end

function Geocoding.search_by_name(name, opts)
    opts = opts or {}
    name = trim(name)
    if name == "" then
        return { ok = false, error_kind = "invalid_input", error = "empty_name" }
    end
    local count = tonumber(opts.count) or 1
    local url = "https://geocoding-api.open-meteo.com/v1/search?name=" .. urlencode(name)
        .. "&count=" .. tostring(count) .. "&language=en&format=json"
    local max_bytes = tonumber(opts.max_bytes) or 131072
    if max_bytes < 16384 then max_bytes = 16384 end
    if max_bytes > 1048576 then max_bytes = 1048576 end
    local res = Http.get_json(url, {
        timeout_s = opts.timeout_s or 10,
        max_bytes = max_bytes,
        retries = 1,
    })
    if not res.ok then
        Logger.warn("geocoding", "search_failed", { name = name, kind = res.error_kind, status = res.status })
        return res
    end
    local data = res.json or {}
    local results = data.results
    if type(results) ~= "table" or #results == 0 then
        return { ok = false, error_kind = "not_found", error = "no_results" }
    end
    local r = results[1]
    local lat = tonumber(r.latitude)
    local lon = tonumber(r.longitude)
    if not lat or not lon then
        return { ok = false, error_kind = "parse", error = "missing_coordinates" }
    end
    local place_parts = {}
    if type(r.name) == "string" and r.name ~= "" then table.insert(place_parts, r.name) end
    if type(r.admin1) == "string" and r.admin1 ~= "" and r.admin1 ~= r.name then table.insert(place_parts, r.admin1) end
    if type(r.country) == "string" and r.country ~= "" then table.insert(place_parts, r.country) end
    local place_name = table.concat(place_parts, ", ")
    if place_name == "" then place_name = name end
    Logger.info("geocoding", "search_ok", { name = name, lat = lat, lon = lon })
    return {
        ok = true,
        lat = lat,
        lon = lon,
        place_name = place_name,
        raw = r,
    }
end

return Geocoding
