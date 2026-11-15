local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Config = {}
Config.__index = Config

local DEFAULTS = {
    refresh_on_open = true,
    show_battery = true,
    show_network = true,
}

local function as_bool(value, default)
    if type(value) == "boolean" then
        return value
    end
    return default
end

function Config:new()
    local o = setmetatable({}, self)
    o.settings_path = DataStorage:getSettingsDir() .. "/kindlehome.lua"
    o.settings = LuaSettings:open(o.settings_path)
    o.values = {}
    o:load()
    return o
end

function Config:load()
    for k, v in pairs(DEFAULTS) do
        local stored = self.settings:readSetting(k)
        if stored == nil then
            self.values[k] = v
        elseif type(v) == "boolean" then
            self.values[k] = as_bool(stored, v)
        else
            self.values[k] = stored
        end
    end
    return self
end

function Config:get(key)
    if self.values[key] ~= nil then
        return self.values[key]
    end
    return DEFAULTS[key]
end

function Config:set(key, value)
    if DEFAULTS[key] == nil then
        return false
    end
    local default = DEFAULTS[key]
    if type(default) == "boolean" then
        value = as_bool(value, default)
    end
    self.values[key] = value
    self.settings:saveSetting(key, value)
    return true
end

function Config:flush()
    self.settings:flush()
end

return Config
