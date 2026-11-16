-- Smoke test: text-input menus must never build a ButtonTable row with a nil
-- hole, and the API-key Clear button must close its own dialog.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local closed = {}
local created = {}

package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        close = function(_, widget) closed[#closed + 1] = widget end,
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

package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, opts) return { text = opts and opts.text } end }
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

print("OK menus smoke: " .. #created .. " input dialogs, no nil button holes")
