-- SPDX-License-Identifier: MIT
local Device = require("device")
local UIManager = require("ui/uimanager")
local CenterContainer = require("ui/widget/container/centercontainer")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local TouchMenu = require("ui/widget/touchmenu")
local _ = require("gettext")

local Geocoding = require("lib/geocoding")
local Theme = require("lib/render/theme")
local Logger = require("lib/logger")
local Messages = require("ui/messages")

local Menus = {}

local function show_info(text, timeout)
    UIManager:show(InfoMessage:new{ text = tostring(text or ""), timeout = timeout or 3 })
end

local function bool_text(v)
    return v and _("On") or _("Off")
end

local function custom_folder_active(config)
    local value = config:get("custom_content_dir")
    return type(value) == "string" and value ~= ""
end

local function refresh_open_view(main_instance, getter, name)
    if not (main_instance and getter) then return end
    local ok, view = pcall(getter, main_instance)
    if not ok or not (view and view.widget) then return end
    if main_instance.settings_menu then
        main_instance.dashboard_refresh_pending = true
        return
    end
    local refreshed, err = pcall(function() view:refresh({ allow_network = false }) end)
    if not refreshed then
        Logger.err("menus", "view_refresh_failed", { view = name, err = tostring(err) })
    end
end

local function refresh_dashboard(main_instance)
    refresh_open_view(main_instance, main_instance and main_instance.getDashboard, "dashboard")
    refresh_open_view(main_instance, main_instance and main_instance.getTodos, "todos")
end

local function mask_key(key)
    if type(key) ~= "string" or key == "" then return _("(not set)") end
    if #key <= 8 then return "********" end
    return string.rep("*", math.min(12, #key - 4)) .. key:sub(-4)
end

local function prompt_text(title, input, hint, on_save, opts)
    opts = opts or {}
    local dialog
    local buttons = {
        {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
        },
    }
    if opts.extra_button then
        local extra = {}
        for k, v in pairs(opts.extra_button) do extra[k] = v end
        local original_callback = extra.callback
        extra.callback = function()
            if original_callback then original_callback(dialog) end
        end
        table.insert(buttons[1], 2, extra)
    end
    table.insert(buttons[1], {
        text = opts.save_text or _("Save"),
        is_enter_default = true,
        callback = function()
            local val = dialog:getInputText() or ""
            local ok, msg = on_save(val, dialog)
            if ok == false then
                show_info(msg or _("Invalid value."))
                return
            end
            UIManager:close(dialog)
            if msg then show_info(msg, opts.success_timeout or 3) end
        end,
    })

    dialog = InputDialog:new{
        title = title,
        input = input or "",
        input_hint = hint,
        description = opts.description,
        text_type = opts.text_type,
        input_type = opts.input_type,
        buttons = buttons,
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Menus:edit_weather_latlon(config, on_done)
    local current_lat = config:get("weather_lat")
    local current_lon = config:get("weather_lon")
    local lat_str = current_lat ~= nil and tostring(current_lat) or ""
    local lon_str = current_lon ~= nil and tostring(current_lon) or ""
    local input = (lat_str ~= "" or lon_str ~= "") and (lat_str .. ", " .. lon_str) or ""
    prompt_text(_("Weather location (lat, lon)"), input, "e.g. 19.4326, -99.1332", function(raw)
        local a, b = raw:match("^%s*([^,;]+)[,;]%s*(.+)%s*$")
        if not a or not b then return false, _("Enter latitude and longitude separated by comma.") end
        local lat = tonumber(a)
        local lon = tonumber(b)
        if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then
            return false, _("Invalid coordinates.")
        end
        config:set("weather_lat", lat)
        config:set("weather_lon", lon)
        config:flush()
        Logger.info("menus", "weather_latlon_saved")
        if on_done then on_done() end
        return true, _("Weather location saved.")
    end)
end

function Menus:edit_weather_place(config, on_done)
    prompt_text(_("Weather place name (search)"), config:get("weather_place_name") or "", "e.g. Mexico City", function(name)
        if name:match("^%s*$") then return false, _("Enter a place name.") end
        local res = Geocoding.search_by_name(name, {
            timeout_s = config:get("http_timeout_s"),
            max_bytes = config:get("http_max_bytes"),
        })
        if not res.ok then
            Logger.warn("menus", "geocoding_failed", { kind = res.error_kind })
            local msg = Messages.for_kind(res.error_kind, _("Place not found."))
            if res.error_kind == "network" or res.error_kind == "timeout" or res.error_kind == "offline" then
                msg = Messages.for_kind(res.error_kind, _("Network error. Turn on WiFi and try again."))
            elseif res.error_kind == "not_found" then
                msg = _("Place not found.")
            end
            return false, msg
        end
        config:set("weather_lat", res.lat)
        config:set("weather_lon", res.lon)
        config:set("weather_place_name", res.place_name or name)
        config:flush()
        Logger.info("menus", "weather_place_saved")
        if on_done then on_done() end
        return true, _("Location set: ") .. tostring(res.place_name)
    end, { save_text = _("Search & save"), success_timeout = 4 })
end

function Menus:edit_hnmd_base_url(config, on_done)
    prompt_text(_("HN base URL (hnmd)"), config:get("hnmd_base_url") or "https://hnmd.miguehm.com", "https://hnmd.miguehm.com", function(val)
        config:set("hnmd_base_url", val)
        config:flush()
        Logger.info("menus", "hnmd_base_url_saved")
        if on_done then on_done() end
        return true, _("HN base URL saved.")
    end)
end

function Menus:edit_hnmd_api_key(config, on_done)
    prompt_text(_("HN API key (Bearer)"), config:get("hnmd_api_key") or "", _("Paste API key (stored locally)"), function(val)
        config:set("hnmd_api_key", val)
        config:flush()
        Logger.info("menus", "hnmd_api_key_saved")
        if on_done then on_done() end
        return true, _("HN API key saved.")
    end, {
        text_type = "password",
        description = _("Current: ") .. mask_key(config:get("hnmd_api_key")),
        extra_button = {
            text = _("Clear"),
            callback = function(dialog)
                config:set("hnmd_api_key", "")
                config:flush()
                UIManager:close(dialog)
                Logger.info("menus", "hnmd_api_key_cleared")
                show_info(_("HN API key cleared."))
                if on_done then on_done() end
            end,
        },
    })
end

function Menus:edit_int(config, key, title, hint, minv, maxv, label, on_done)
    prompt_text(title, tostring(config:get(key) or ""), hint, function(raw)
        local n = tonumber(raw)
        if not n then return false, _("Enter a number.") end
        n = math.floor(n)
        if n < minv or n > maxv then return false, string.format(_("Enter a value between %d and %d."), minv, maxv) end
        config:set(key, n)
        config:flush()
        Logger.info("menus", "setting_saved", { key = key })
        if on_done then on_done() end
        return true, (label or key) .. ": " .. tostring(config:get(key))
    end, { input_type = "number" })
end

function Menus:edit_documents_subdir(config, on_done)
    prompt_text(_("Documents subdir"), config:get("documents_subdir") or "KindleHome", "KindleHome", function(val)
        val = tostring(val or ""):gsub("[/\\]", ""):match("^%s*(.-)%s*$") or ""
        if val == "" then val = "KindleHome" end
        config:set("documents_subdir", val)
        config:flush()
        Logger.info("menus", "documents_subdir_saved")
        if on_done then on_done() end
        return true, _("Documents subdir saved.")
    end)
end

local function apply_custom_content_dir(config, paths, value, on_done, message_kind)
    value = tostring(value or "")
    if config.validate_custom_dir and not config:validate_custom_dir(value) then
        show_info(Messages.for_kind("path_invalid", _("Invalid folder path.")))
        return false
    end
    config:set("custom_content_dir", value)
    config:flush()
    local ok, ensured = true, true
    if type(paths and paths.ensure_base_dirs) == "function" then
        ok, ensured = pcall(function() return paths:ensure_base_dirs() end)
    end
    if not ok or not ensured then
        Logger.warn("menus", "custom_dir_not_ready", { err = tostring(ensured) })
        if on_done then on_done() end
        show_info(Messages.for_kind("path_unwritable", _("Folder could not be created.")))
        return false
    end
    Logger.info("menus", "custom_content_dir_saved")
    if on_done then on_done() end
    show_info(Messages.for_kind(message_kind or "path_saved", _("Custom content folder saved.")))
    return true
end

function Menus:edit_custom_content_dir(config, paths, on_done)
    local current = config:get("custom_content_dir")
    if type(current) ~= "string" or current == "" then
        current = type(paths and paths.documents_root) == "function" and paths:documents_root() or nil
    end
    local opts = {
        title = _("Choose custom content folder"),
        select_directory = true,
        select_file = false,
        show_files = false,
        onConfirm = function(dir_path)
            apply_custom_content_dir(config, paths, dir_path, on_done, "path_saved")
        end,
    }
    if type(current) == "string" and current ~= "" then
        opts.path = current
    end
    UIManager:show(PathChooser:new(opts))
end

function Menus:reset_custom_content_dir(config, paths, on_done)
    apply_custom_content_dir(config, paths, "", on_done, "path_reset")
end

function Menus:settings_items(main_instance)
    local config = main_instance.config
    local paths = main_instance.paths

    local items = {
            {
                text = _("Weather"),
                sub_item_table = {
                    {
                        text_func = function() return _("Weather enabled: ") .. bool_text(config:get("weather_enabled")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("weather_enabled") and true or false end,
                        callback = function()
                            config:set("weather_enabled", not config:get("weather_enabled")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("Show weather section: ") .. bool_text(config:get("show_weather")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("show_weather") and true or false end,
                        callback = function()
                            config:set("show_weather", not config:get("show_weather")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text = _("Set location (search)"),
                        keep_menu_open = true,
                        callback = function() Menus:edit_weather_place(config, function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text = _("Set coordinates (lat, lon)"),
                        keep_menu_open = true,
                        callback = function() Menus:edit_weather_latlon(config, function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text = _("Clear location"),
                        keep_menu_open = true,
                        callback = function()
                            config:set("weather_lat", nil); config:set("weather_lon", nil); config:set("weather_place_name", ""); config:flush()
                            show_info(_("Weather location cleared.")); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("Weather TTL (minutes): ") .. tostring(config:get("weather_ttl_minutes")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "weather_ttl_minutes", _("Weather TTL (minutes)"), "60", 1, 10080, _("Weather TTL"), function() refresh_dashboard(main_instance) end) end,
                    },
                },
            },
            {
                text = _("Hacker News"),
                sub_item_table = {
                    {
                        text_func = function() return _("HN enabled: ") .. bool_text(config:get("hnmd_enabled")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("hnmd_enabled") and true or false end,
                        callback = function()
                            config:set("hnmd_enabled", not config:get("hnmd_enabled")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("Show HN section: ") .. bool_text(config:get("show_hn")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("show_hn") and true or false end,
                        callback = function()
                            config:set("show_hn", not config:get("show_hn")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("Base URL: ") .. tostring(config:get("hnmd_base_url")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_hnmd_base_url(config, function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function() return _("API key: ") .. mask_key(config:get("hnmd_api_key")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_hnmd_api_key(config, function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function() return _("Max items: ") .. tostring(config:get("hnmd_max_items")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "hnmd_max_items", _("HN max items (1-20)"), "10", 1, 20, _("HN max items"), function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function() return _("Items per page: ") .. tostring(config:get("hn_items_per_page")) end,
                        keep_menu_open = true,
                        callback = function()
                            Menus:edit_int(config, "hn_items_per_page", _("HN items per page (1-10)"), "4", 1, 10, _("HN items per page"), function()
                                local d = main_instance and main_instance.getDashboard and main_instance:getDashboard()
                                if d and d.reset_hn_page then d:reset_hn_page() end
                                refresh_dashboard(main_instance)
                            end)
                        end,
                    },
                    {
                        text_func = function() return _("HN TTL (minutes): ") .. tostring(config:get("hnmd_ttl_minutes")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "hnmd_ttl_minutes", _("HN TTL (minutes)"), "30", 1, 10080, _("HN TTL"), function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text = _("Manual config note"),
                        keep_menu_open = true,
                        callback = function()
                            show_info(_("API key/base URL can also be edited in settings/kindlehome.lua."), 5)
                        end,
                    },
                },
            },
            {
                text = _("TODO'S"),
                sub_item_table = {
                    {
                        text_func = function() return _("TODO'S enabled: ") .. bool_text(config:get("todos_enabled")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("todos_enabled") and true or false end,
                        callback = function()
                            config:set("todos_enabled", not config:get("todos_enabled")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("Show tag filters: ") .. bool_text(config:get("todos_include_tags")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("todos_include_tags") and true or false end,
                        callback = function()
                            config:set("todos_include_tags", not config:get("todos_include_tags")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("TODO'S TTL (minutes): ") .. tostring(config:get("todos_ttl_minutes")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "todos_ttl_minutes", _("TODO'S TTL (minutes)"), "5", 1, 10080, _("TODO'S TTL"), function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text = _("Write permissions"),
                        keep_menu_open = true,
                        callback = function()
                            show_info(_("Adding and updating tasks uses the HN API key. The server must allow writes (API_KEYS or TODO_ALLOW_INSECURE_WRITES)."), 7)
                        end,
                    },
                },
            },
            {
                text = _("Sections"),
                sub_item_table = {
                    {
                        text_func = function() return _("Show battery: ") .. bool_text(config:get("show_battery")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("show_battery") and true or false end,
                        callback = function() config:set("show_battery", not config:get("show_battery")); config:flush(); refresh_dashboard(main_instance) end,
                    },
                    {
                        text_func = function() return _("Show network: ") .. bool_text(config:get("show_network")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("show_network") and true or false end,
                        callback = function() config:set("show_network", not config:get("show_network")); config:flush(); refresh_dashboard(main_instance) end,
                    },
                },
            },
            {
                text = _("Interface"),
                sub_item_table = {
                    {
                        text_func = function()
                            return _("Text size: ") .. Theme.scale_label(config:get("ui_font_scale"))
                        end,
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = _("Small"),
                                checked_func = function() return Theme.normalize_scale(config:get("ui_font_scale")) <= 0.95 end,
                                callback = function()
                                    config:set("ui_font_scale", 0.9); config:flush(); refresh_dashboard(main_instance)
                                end,
                            },
                            {
                                text = _("Medium"),
                                checked_func = function() return Theme.normalize_scale(config:get("ui_font_scale")) > 0.95 and Theme.normalize_scale(config:get("ui_font_scale")) <= 1.1 end,
                                callback = function()
                                    config:set("ui_font_scale", 1.0); config:flush(); refresh_dashboard(main_instance)
                                end,
                            },
                            {
                                text = _("Large"),
                                checked_func = function() return Theme.normalize_scale(config:get("ui_font_scale")) > 1.1 and Theme.normalize_scale(config:get("ui_font_scale")) <= 1.3 end,
                                callback = function()
                                    config:set("ui_font_scale", 1.25); config:flush(); refresh_dashboard(main_instance)
                                end,
                            },
                            {
                                text = _("Extra large"),
                                checked_func = function() return Theme.normalize_scale(config:get("ui_font_scale")) > 1.3 end,
                                callback = function()
                                    config:set("ui_font_scale", 1.45); config:flush(); refresh_dashboard(main_instance)
                                end,
                            },
                        },
                    },
                    {
                        text_func = function() return _("Full screen: ") .. bool_text(config:get("ui_fullscreen")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("ui_fullscreen") and true or false end,
                        callback = function()
                            config:set("ui_fullscreen", not config:get("ui_fullscreen")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function() return _("24-hour clock: ") .. bool_text(config:get("ui_clock_24h")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("ui_clock_24h") and true or false end,
                        callback = function()
                            config:set("ui_clock_24h", not config:get("ui_clock_24h")); config:flush(); refresh_dashboard(main_instance)
                        end,
                    },
                },
            },
            {
                text = _("Refresh and network"),
                sub_item_table = {
                    {
                        text_func = function() return _("Refresh on open: ") .. bool_text(config:get("refresh_on_open")) end,
                        keep_menu_open = true,
                        checked_func = function() return config:get("refresh_on_open") and true or false end,
                        callback = function() config:set("refresh_on_open", not config:get("refresh_on_open")); config:flush() end,
                    },
                    {
                        text_func = function() return _("Refresh budget (s): ") .. tostring(config:get("refresh_budget_s")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "refresh_budget_s", _("Refresh budget (seconds)"), "20", 1, 120, _("Refresh budget"), function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function() return _("HTTP timeout (s): ") .. tostring(config:get("http_timeout_s")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "http_timeout_s", _("HTTP timeout (seconds)"), "10", 1, 60, _("HTTP timeout"), function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function() return _("HTTP max bytes: ") .. tostring(config:get("http_max_bytes")) end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_int(config, "http_max_bytes", _("HTTP max bytes"), "524288", 16384, 10485760, _("HTTP max bytes"), function() refresh_dashboard(main_instance) end) end,
                    },
                },
            },
            {
                text = _("Paths and storage"),
                sub_item_table = {
                    {
                        text_func = function()
                            local suffix = custom_folder_active(config) and _(" (fallback)") or ""
                            return _("Storage mode: ") .. tostring(config:get("storage_mode")) .. suffix
                        end,
                        keep_menu_open = true,
                        callback = function()
                            local current = config:get("storage_mode")
                            config:set("storage_mode", current == "documents" and "datadir" or "documents")
                            config:flush()
                            show_info(_("Storage mode: ") .. tostring(config:get("storage_mode")))
                            refresh_dashboard(main_instance)
                        end,
                    },
                    {
                        text_func = function()
                            local suffix = custom_folder_active(config) and _(" (fallback)") or ""
                            return _("Documents subdir: ") .. tostring(config:get("documents_subdir")) .. suffix
                        end,
                        keep_menu_open = true,
                        callback = function() Menus:edit_documents_subdir(config, function() refresh_dashboard(main_instance) end) end,
                    },
                    {
                        text_func = function()
                            local value = config:get("custom_content_dir")
                            return _("Choose custom content folder: ") .. ((type(value) == "string" and value ~= "") and value or _("(not set)"))
                        end,
                        keep_menu_open = true,
                        callback = function()
                            Menus:edit_custom_content_dir(config, paths, function()
                                refresh_dashboard(main_instance)
                            end)
                        end,
                    },
                    {
                        text = _("Reset custom content folder"),
                        keep_menu_open = true,
                        callback = function()
                            Menus:reset_custom_content_dir(config, paths, function()
                                refresh_dashboard(main_instance)
                            end)
                        end,
                    },
                    {
                        text = _("Show active content paths"),
                        keep_menu_open = true,
                        callback = function()
                            if not paths then return show_info(_("Paths unavailable.")) end
                            local msg = table.concat({
                                _("Cache: ") .. tostring(paths:cache_dir()),
                                _("Content: ") .. tostring(paths:documents_root()),
                                _("HN articles: ") .. tostring(paths:articles_hn_dir()),
                            }, "\n")
                            show_info(msg, 8)
                        end,
                    },
                },
            },
        }

    return items
end

function Menus:add_settings(menu_items, main_instance)
    menu_items.kindlehome = {
        text = _("Kindle Home"),
        sorting_hint = "tools",
        callback = function() main_instance:onKindlehomeShowDashboard() end,
    }
end

function Menus:show_settings(main_instance)
    if main_instance.settings_menu then return end
    local screen = Device.screen
    local items = Menus:settings_items(main_instance)
    items.text = _("Kindle Home")
    items.icon = "appbar.settings"

    local container = CenterContainer:new{
        covers_header = true,
        ignore = "height",
        dimen = screen:getSize(),
    }
    local menu = TouchMenu:new{
        width = screen:getWidth(),
        tab_item_table = { items },
        show_parent = container,
    }

    local closed = false
    local function close_menu()
        if closed then return end
        closed = true
        UIManager:close(container)
        main_instance.settings_menu = nil
        if main_instance.dashboard_refresh_pending then
            main_instance.dashboard_refresh_pending = nil
            refresh_dashboard(main_instance)
        end
    end
    menu.close_callback = close_menu
    container[1] = menu

    main_instance.settings_menu = container
    UIManager:show(container)
end

return Menus
