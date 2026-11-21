-- SPDX-License-Identifier: MIT
-- Smoke test: Config defaults/sanitization and optional (nil-default) keys.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local store = {}

package.preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/settings" end,
    }
end
package.preload["luasettings"] = function()
    return {
        open = function()
            return {
                readSetting = function(_, key) return store[key] end,
                saveSetting = function(_, key, value) store[key] = value end,
                flush = function() end,
            }
        end,
    }
end

local Config = dofile(PLUGIN .. "lib/config.lua")

local c = Config:new()
assert(c:get("weather_lat") == nil, "weather_lat must default to nil")
assert(c:get("weather_lon") == nil, "weather_lon must default to nil")

assert(c:set("weather_lat", 19.4326) == true, "optional key must be settable")
assert(c:set("weather_lon", -99.1332) == true, "optional key must be settable")
assert(c:get("weather_lat") == 19.4326, "weather_lat not saved in memory")
assert(c:get("weather_lon") == -99.1332, "weather_lon not saved in memory")
c:flush()

local reloaded = Config:new()
assert(reloaded:get("weather_lat") == 19.4326, "weather_lat must survive reload")
assert(reloaded:get("weather_lon") == -99.1332, "weather_lon must survive reload")

assert(reloaded:set("weather_lat", 200) == true, "out-of-range value must be accepted then sanitized")
assert(reloaded:get("weather_lat") == nil, "out-of-range coordinate must fall back to nil")
assert(reloaded:set("weather_lat", nil) == true, "clearing an optional key must succeed")
assert(reloaded:get("weather_lat") == nil, "cleared coordinate must be nil")
assert(reloaded:set("unknown_key", 1) == false, "unknown keys must still be rejected")

assert(reloaded:set("hnmd_max_items", 99) == true, "clamped key must be settable")
assert(reloaded:get("hnmd_max_items") == 20, "hnmd_max_items must clamp to 20")

assert(reloaded:get("hn_items_per_page") == 4, "hn_items_per_page must default to 4")
assert(reloaded:set("hn_items_per_page", 99) == true, "hn_items_per_page must be settable")
assert(reloaded:get("hn_items_per_page") == 10, "hn_items_per_page must clamp to 10")
assert(reloaded:set("hn_items_per_page", 0) == true, "hn_items_per_page must accept out-of-range input")
assert(reloaded:get("hn_items_per_page") == 1, "hn_items_per_page must clamp to 1")

assert(c:get("custom_content_dir") == "", "custom content folder must default to disabled")
assert(c:validate_custom_dir("/mnt/us/My Docs/Kindle//HN/") == true, "absolute nested path must validate")
assert(c:validate_custom_dir("relative/path") == false, "relative path must be rejected")
assert(c:validate_custom_dir("/mnt/us/../koreader") == false, "parent traversal must be rejected")
assert(c:validate_custom_dir("") == true, "empty value must disable the override")
assert(c:set("custom_content_dir", "/mnt/us/My Docs/Kindle//HN/") == true, "custom path must be settable")
assert(c:get("custom_content_dir") == "/mnt/us/My Docs/Kindle/HN", "custom path must be normalized")
c:flush()
local with_custom = Config:new()
assert(with_custom:get("custom_content_dir") == "/mnt/us/My Docs/Kindle/HN", "custom path must survive reload")
assert(with_custom:set("custom_content_dir", "relative") == true, "invalid path must be accepted then sanitized")
assert(with_custom:get("custom_content_dir") == "", "invalid path must fall back to disabled")
assert(with_custom:set("custom_content_dir", "/mnt/us/koreader/plugins") == true, "koreader install path must be rejected")
assert(with_custom:get("custom_content_dir") == "", "koreader install path must fall back to disabled")
assert(with_custom:set("documents_subdir", "..") == true, "traversal in subdir must be accepted then sanitized")
assert(with_custom:get("documents_subdir") == "KindleHome", "traversal in subdir must fall back to default")

print("OK config smoke: optional coordinates, path safety and custom content folder")
