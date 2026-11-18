-- Smoke test: text-input menus must never build a ButtonTable row with a nil
-- hole, the API-key Clear button must close its own dialog, and the custom
-- content folder is chosen with KOReader's native PathChooser.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local closed = {}
local created = {}
local pickers = {}
local messages = {}
local shown = {}
local touch_menus = {}

package.preload["ui/uimanager"] = function()
    return {
        show = function(_, widget) shown[#shown + 1] = widget end,
        close = function(_, widget) closed[#closed + 1] = widget end,
    }
end

package.preload["device"] = function()
    return {
        screen = {
            getWidth = function() return 1200 end,
            getSize = function() return { w = 1200, h = 1600 } end,
        },
    }
end

package.preload["ui/widget/container/centercontainer"] = function()
    return {
        new = function(_, opts)
            opts.getSize = function(self) return self.dimen end
            return opts
        end,
    }
end

package.preload["ui/widget/touchmenu"] = function()
    return {
        new = function(_, opts)
            local menu = { opts = opts }
            touch_menus[#touch_menus + 1] = menu
            return menu
        end,
    }
end

package.preload["ui/widget/inputdialog"] = function()
    return {
        new = function(_, opts)
            -- Mimic KOReader's ButtonTable:init: it walks 1..#row and dereferences
            -- row[j], so a bare nil (old opts.extra_button) crashes on device.
            for _, row in ipairs(opts.buttons or {}) do
                for j = 1, #row do
                    local entry = row[j]
                    local _ = entry.text
                end
            end
            local dlg = {
                opts = opts,
                input = opts.input or "",
                getInputText = function(self) return self.input end,
                onShowKeyboard = function() end,
            }
            created[#created + 1] = dlg
            return dlg
        end,
    }
end

package.preload["ui/widget/pathchooser"] = function()
    return {
        new = function(_, opts)
            local picker = { opts = opts }
            pickers[#pickers + 1] = picker
            return picker
        end,
    }
end

package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, opts)
        local msg = { text = opts and opts.text }
        messages[#messages + 1] = msg
        return msg
    end }
end
package.preload["gettext"] = function()
    return function(s) return s end
end
package.preload["lib/logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
    }
end
package.preload["lib/geocoding"] = function()
    return {
        search_by_name = function()
            return { ok = true, lat = 19.43, lon = -99.13, place_name = "Mexico City" }
        end,
    }
end
package.preload["lib/render/theme"] = function()
    return {
        scale_label = function() return "Medium" end,
        normalize_scale = function() return 1.0 end,
        font_size = function() return 20 end,
        native_size = function(_, v) return v end,
    }
end

local Menus = dofile(PLUGIN .. "ui/menus.lua")

local values = {}
local cfg = {
    get = function(_, key) return values[key] end,
    set = function(_, key, value) values[key] = value; return true end,
    flush = function() end,
    validate_custom_dir = function(_, value)
        if value == "" then return true end
        if value:sub(1, 1) ~= "/" then return false end
        for segment in value:gmatch("[^/]+") do
            if segment == ".." then return false end
        end
        return true
    end,
}
local dirs_ready = true
local paths_stub = {
    ensure_base_dirs = function() return dirs_ready end,
    cache_dir = function() return "/cache/kindlehome" end,
    documents_root = function() return values.custom_content_dir ~= "" and values.custom_content_dir or "/documents/KindleHome" end,
    articles_hn_dir = function() return "/documents/KindleHome/articles/hn" end,
}

local function last_dialog()
    return created[#created]
end
local function button(dlg, index)
    return dlg.opts.buttons[1][index]
end
local function click(dlg, index)
    local btn = button(dlg, index)
    assert(type(btn) == "table" and type(btn.callback) == "function", "button callback missing")
    btn.callback()
end

local done = 0
local function on_done() done = done + 1 end

Menus:edit_weather_latlon(cfg, on_done)
local d = last_dialog()
assert(#d.opts.buttons[1] == 2, "dialog without extra button must have exactly two buttons")
d.input = "19.43, -99.13"
click(d, 2)
assert(values.weather_lat == 19.43 and values.weather_lon == -99.13, "coordinates not saved")
assert(done == 1, "on_done not called after saving coordinates")

Menus:edit_weather_place(cfg, on_done)
d = last_dialog()
assert(#d.opts.buttons[1] == 2, "place dialog must have no nil button hole")
assert(button(d, 2).text == "Search & save", "search button label missing")
d.input = "Mexico City"
click(d, 2)
assert(values.weather_place_name == "Mexico City", "place name not saved")
assert(values.weather_lat == 19.43 and values.weather_lon == -99.13, "geocoded coordinates not saved")
assert(done == 2, "on_done not called after place search")

Menus:edit_int(cfg, "weather_ttl_minutes", "Weather TTL", "60", 1, 10080, "Weather TTL")
d = last_dialog()
d.input = "90"
click(d, 2)
assert(values.weather_ttl_minutes == 90, "numeric setting not saved")

Menus:edit_documents_subdir(cfg, on_done)
d = last_dialog()
assert(#d.opts.buttons[1] == 2, "documents subdir dialog must have no nil hole")
d.input = "My Docs/"
click(d, 2)
assert(values.documents_subdir == "My Docs", "documents subdir not sanitized/saved")

Menus:edit_hnmd_base_url(cfg, on_done)
d = last_dialog()
d.input = "https://example.com"
click(d, 2)
assert(values.hnmd_base_url == "https://example.com", "base URL not saved")

values.hnmd_api_key = "secret-1234"
Menus:edit_hnmd_api_key(cfg, on_done)
d = last_dialog()
assert(#d.opts.buttons[1] == 3, "API key dialog must have Cancel, Clear and Save")
assert(button(d, 2).text == "Clear", "Clear button missing")
local before = #closed
button(d, 2).callback()
assert(values.hnmd_api_key == "", "Clear must remove the API key")
assert(#closed == before + 1 and closed[#closed] == d, "Clear must close its own dialog")
assert(done == 5, "on_done not called after Clear")

values.custom_content_dir = ""
local function last_picker()
    return pickers[#pickers]
end
local function choose(path)
    local picker = last_picker()
    assert(type(picker.opts.onConfirm) == "function", "picker onConfirm missing")
    picker.opts.onConfirm(path)
end

Menus:edit_custom_content_dir(cfg, paths_stub, on_done)
local picker = last_picker()
assert(picker.opts.select_directory == true and picker.opts.select_file == false
    and picker.opts.show_files == false, "picker must be directory-only")
assert(picker.opts.path == "/documents/KindleHome", "picker must start at the active content root")
choose("/mnt/us/My Docs/Kindle")
assert(values.custom_content_dir == "/mnt/us/My Docs/Kindle", "picked folder not saved")
assert(done == 6, "on_done not called after choosing a folder")
assert(messages[#messages].text == "Custom content folder saved.", "path_saved message missing")

Menus:edit_custom_content_dir(cfg, paths_stub, on_done)
assert(last_picker().opts.path == "/mnt/us/My Docs/Kindle", "picker must start at the current custom folder")
choose("/mnt/us/../etc")
assert(values.custom_content_dir == "/mnt/us/My Docs/Kindle", "invalid folder must not overwrite the saved value")
assert(done == 6, "on_done must not run for an invalid folder")
assert(messages[#messages].text == "Use an absolute path such as /mnt/us/My Docs. Paths with '..' are not allowed.", "path_invalid message missing")

dirs_ready = false
Menus:edit_custom_content_dir(cfg, paths_stub, on_done)
choose("/mnt/us/Unwritable")
assert(values.custom_content_dir == "/mnt/us/Unwritable", "folder is saved even if it cannot be created yet")
assert(messages[#messages].text == "Folder saved, but it could not be created. Check the path and permissions.", "path_unwritable message missing")
dirs_ready = true

Menus:reset_custom_content_dir(cfg, paths_stub, on_done)
assert(values.custom_content_dir == "", "reset must clear the custom folder")
assert(done == 8, "on_done not called after reset")
assert(messages[#messages].text == "Custom content folder cleared. Using the default location.", "path_reset message missing")

local dashboard = { widget = {}, last_test_doc = { md_path = "/old/doc.md" } }
local refresh_calls = 0
function dashboard:refresh() refresh_calls = refresh_calls + 1 end
local opened_dashboard = 0
local main_instance = {
    config = cfg,
    paths = paths_stub,
    getDashboard = function() return dashboard end,
    onKindlehomeShowDashboard = function() opened_dashboard = opened_dashboard + 1 end,
}
local menu_items = {}
Menus:add_settings(menu_items, main_instance)
assert(type(menu_items.kindlehome.callback) == "function"
    and menu_items.kindlehome.sub_item_table == nil,
    "Tools entry must open the dashboard directly")
menu_items.kindlehome.callback()
assert(opened_dashboard == 1, "Tools callback must open the dashboard")

local settings_items = Menus:settings_items(main_instance)
local paths_menu
for _, item in ipairs(settings_items) do
    if item.text == "Paths and storage" then paths_menu = item.sub_item_table end
end
assert(paths_menu, "Paths and storage menu missing")
local picker_entry
for _, item in ipairs(paths_menu) do
    if type(item.text_func) == "function" and item.text_func():match("^Choose custom content folder") then
        picker_entry = item
    end
end
assert(picker_entry and picker_entry.keep_menu_open, "picker menu entry missing")
picker_entry.callback()
choose("/mnt/us/From Menu")
assert(values.custom_content_dir == "/mnt/us/From Menu", "menu callback did not apply the picked path")
assert(dashboard.last_test_doc == nil, "menu callback must clear last_test_doc")
assert(refresh_calls == 1, "menu callback must refresh the open dashboard")

Menus:show_settings(main_instance)
assert(#touch_menus == 1 and shown[#shown] ~= nil, "in-dashboard settings menu must be a shown TouchMenu")
local settings_menu = touch_menus[1]
local tab = settings_menu.opts.tab_item_table[1]
assert(tab.icon == "appbar.settings" and #settings_menu.opts.tab_item_table == 1,
    "settings menu must use one native tab")
assert(#tab.item_table == #settings_items, "settings menu must reuse the plugin settings sections")
for _, item in ipairs(tab.item_table) do
    assert(item.text ~= "Open dashboard", "dashboard settings must not expose Open dashboard")
end
assert(settings_menu.opts.show_parent == shown[#shown] and main_instance.settings_menu == shown[#shown],
    "settings menu must own its container")
local weather_menu
for _, item in ipairs(tab.item_table) do
    if item.text == "Weather" then weather_menu = item.sub_item_table end
end
assert(weather_menu and type(weather_menu[1].callback) == "function", "weather settings missing")
weather_menu[1].callback()
assert(refresh_calls == 1 and main_instance.dashboard_refresh_pending == true,
    "setting changes must defer the dashboard repaint while the menu is open")
settings_menu.close_callback()
assert(refresh_calls == 2 and main_instance.settings_menu == nil
    and main_instance.dashboard_refresh_pending == nil,
    "closing the settings menu must flush the deferred repaint")
Menus:show_settings(main_instance)
assert(#touch_menus == 2, "settings menu must be reopenable after closing")

print("OK menus smoke: " .. #created .. " dialogs, " .. #pickers .. " folder pickers, "
    .. #touch_menus .. " settings menus, no nil button holes")
