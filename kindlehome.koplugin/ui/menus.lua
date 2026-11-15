local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local Geocoding = require("lib/geocoding")
local Logger = require("lib/logger")

local Menus = {}

local function show_info(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

function Menus:edit_weather_latlon(config, on_done)
    local current_lat = config:get("weather_lat")
    local current_lon = config:get("weather_lon")
    local lat_str = current_lat ~= nil and tostring(current_lat) or ""
    local lon_str = current_lon ~= nil and tostring(current_lon) or ""
    local dialog
    dialog = InputDialog:new{
        title = "Weather location (lat, lon)",
        input = (lat_str ~= "" or lon_str ~= "") and (lat_str .. ", " .. lon_str) or "",
        input_hint = "e.g. 19.4326, -99.1332",
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "Save",
                    is_enter_default = true,
                    callback = function()
                        local raw = dialog:getInputText() or ""
                        local a, b = raw:match("^%s*([^,;]+)[,;]%s*(.+)%s*$")
                        if not a or not b then
                            show_info("Enter latitude and longitude separated by comma.")
                            return
                        end
                        local lat = tonumber(a)
                        local lon = tonumber(b)
                        if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then
                            show_info("Invalid coordinates.")
                            return
                        end
                        config:set("weather_lat", lat)
                        config:set("weather_lon", lon)
                        config:flush()
                        UIManager:close(dialog)
                        Logger.info("menus", "weather_latlon_saved", { lat = lat, lon = lon })
                        show_info("Weather location saved.")
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Menus:edit_weather_place(config, on_done)
    local dialog
    dialog = InputDialog:new{
        title = "Weather place name (search)",
        input = config:get("weather_place_name") or "",
        input_hint = "e.g. Mexico City",
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "Search & save",
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText() or ""
                        if name:match("^%s*$") then
                            show_info("Enter a place name.")
                            return
                        end
                        UIManager:close(dialog)
                        local res = Geocoding.search_by_name(name, {
                            timeout_s = config:get("http_timeout_s"),
                            max_bytes = config:get("http_max_bytes"),
                        })
                        if not res.ok then
                            local msg = "Place not found."
                            if res.error_kind == "network" or res.error_kind == "timeout" then
                                msg = "Network error. Turn on WiFi and try again."
                            end
                            show_info(msg, 4)
                            Logger.warn("menus", "geocoding_failed", { kind = res.error_kind })
                            return
                        end
                        config:set("weather_lat", res.lat)
                        config:set("weather_lon", res.lon)
                        config:set("weather_place_name", res.place_name or name)
                        config:flush()
                        Logger.info("menus", "weather_place_saved", { place = res.place_name, lat = res.lat, lon = res.lon })
                        show_info("Location set: " .. tostring(res.place_name), 4)
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Menus:register(main_instance)
    local config = main_instance.config
    local menu_items = require("ui/elements/menu_items")

    -- Extend Tools menu with Kindle Home settings (minimal F4 fields)
    menu_items.kindlehome_settings = {
        text = "Kindle Home",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Weather: set location (search)",
                keep_menu_open = true,
                callback = function()
                    Menus:edit_weather_place(config, function()
                        local d = main_instance:getDashboard()
                        if d then d:refresh() end
                    end)
                end,
            },
            {
                text = "Weather: set coordinates (lat, lon)",
                keep_menu_open = true,
                callback = function()
                    Menus:edit_weather_latlon(config, function()
                        local d = main_instance:getDashboard()
                        if d then d:refresh() end
                    end)
                end,
            },
            {
                text = "Weather: clear location",
                keep_menu_open = true,
                callback = function()
                    config:set("weather_lat", nil)
                    config:set("weather_lon", nil)
                    config:set("weather_place_name", "")
                    config:flush()
                    show_info("Weather location cleared.")
                    local d = main_instance:getDashboard()
                    if d then d:refresh() end
                end,
            },
            {
                text = "Weather enabled",
                checked_func = function() return config:get("weather_enabled") and true or false end,
                callback = function()
                    config:set("weather_enabled", not config:get("weather_enabled"))
                    config:flush()
                    local d = main_instance:getDashboard()
                    if d then d:refresh() end
                end,
            },
            {
                text = "Refresh on open",
                checked_func = function() return config:get("refresh_on_open") and true or false end,
                callback = function()
                    config:set("refresh_on_open", not config:get("refresh_on_open"))
                    config:flush()
                end,
            },
        },
    }
end

return Menus
