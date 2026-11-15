local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local _ = require("gettext")

local Logger = require("lib/logger")

local Dashboard = {}

function Dashboard:new(opts)
    local o = {
        config = opts and opts.config or nil,
        widget = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

local function escape_html(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function get_clock_state()
    local ok_time, t = pcall(os.date, "*t")
    local ok_str, date_str = pcall(os.date, "%A, %B %d, %Y")
    local ok_hm, time_str = pcall(os.date, "%H:%M")
    if not (ok_time and t and ok_str and ok_hm) then
        return "Date unavailable", "Time unavailable"
    end
    return date_str, time_str
end

local function get_battery_state(config)
    if config and not config:get("show_battery") then
        return "Battery: hidden"
    end
    local ok, powerd = pcall(function() return Device:getPowerDevice() end)
    if not ok or not powerd then
        return "Battery: unavailable"
    end
    local parts = {}
    local ok_cap, cap = pcall(function() return powerd:getCapacity() end)
    if ok_cap and cap ~= nil then
        table.insert(parts, tostring(cap) .. "%")
    end
    local charging = nil
    if type(powerd.isCharging) == "function" then
        local ok_c, c = pcall(function() return powerd:isCharging() end)
        if ok_c then charging = c end
    elseif type(powerd.is_charging) == "function" then
        local ok_c, c = pcall(function() return powerd:is_charging() end)
        if ok_c then charging = c end
    end
    if charging == true then
        table.insert(parts, "charging")
    elseif charging == false and #parts > 0 then
        table.insert(parts, "not charging")
    end
    if #parts == 0 then
        return "Battery: unavailable"
    end
    return "Battery: " .. table.concat(parts, ", ")
end

local function get_network_state(config)
    if config and not config:get("show_network") then
        return "Network: hidden"
    end
    local connected = false
    local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
    if ok_conn then
        connected = conn and true or false
    end
    if not connected then
        return "Network: disconnected"
    end
    local ssid = nil
    local ok_info, info = pcall(function()
        if type(NetworkMgr.getNetworkInfo) == "function" then
            return NetworkMgr:getNetworkInfo()
        end
        if type(NetworkMgr.getCurrentNetwork) == "function" then
            return NetworkMgr:getCurrentNetwork()
        end
        return nil
    end)
    if ok_info and type(info) == "table" then
        ssid = info.ssid or info.SSID
    end
    if type(ssid) == "string" and ssid ~= "" then
        return "Network: connected (" .. ssid .. ")"
    end
    return "Network: connected"
end

function Dashboard:build_state()
    local date_str, time_str = get_clock_state()
    local state = {
        date = date_str,
        time = time_str,
        battery = get_battery_state(self.config),
        network = get_network_state(self.config),
    }
    Logger.info("dashboard", "state_built", {
        has_time = state.time ~= "Time unavailable",
        battery = state.battery,
        network = state.network,
    })
    return state
end

local function build_html(state)
    return table.concat({
        "<html><head><style>",
        "body{font-family:sans-serif;margin:24px;color:#111;background:#fff;}",
        "h1{font-size:30px;margin:0 0 8px 0;}",
        "h2{font-size:22px;margin:0 0 18px 0;font-weight:normal;}",
        ".section{margin:18px 0;padding-top:12px;border-top:1px solid #333;}",
        ".label{font-size:18px;margin:6px 0;}",
        ".muted{font-size:16px;color:#444;margin-top:18px;}",
        "</style></head><body>",
        "<h1>Kindle Home</h1>",
        "<h2>", escape_html(state.date), "</h2>",
        "<div class='label'><b>Time:</b> ", escape_html(state.time), "</div>",
        "<div class='section'>",
        "<div class='label'>", escape_html(state.battery), "</div>",
        "<div class='label'>", escape_html(state.network), "</div>",
        "</div>",
        "<p class='muted'>Offline dashboard (Phase 1). Refresh to update local status. Scroll position may reset on refresh.</p>",
        "</body></html>",
    })
end

function Dashboard:show()
    -- Single refresh contract: rebuild local state/HTML and (re)open widget in a controlled way.
    -- Note: replacing the widget resets scroll position (accepted in Phase 1).
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    local state = self:build_state()
    local html = build_html(state)
    self.widget = ScrollHtmlWidget:new{
        html_body = html,
        css = "",
        default_font_size = Screen:scaleBySize(20),
        title = _("Kindle Home"),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        actions = {
            {
                text = _("Refresh"),
                callback = function()
                    self:refresh()
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    self:close()
                end,
            },
        },
    }
    UIManager:show(self.widget)
    Logger.info("dashboard", "shown")
end

function Dashboard:refresh()
    Logger.info("dashboard", "refresh")
    self:show()
end

function Dashboard:close()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
    Logger.info("dashboard", "closed")
end

return Dashboard
