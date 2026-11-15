local UIManager = require("ui/uimanager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local _ = require("gettext")
local Screen = require("device").screen

local Dashboard = {}

function Dashboard:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.widget = nil
    return o
end

local function build_html()
    return table.concat({
        "<html><head><style>",
        "body{font-family:sans-serif;margin:24px;}",
        "h1{font-size:28px;margin-bottom:8px;}",
        "p{font-size:18px;line-height:1.4;}",
        ".muted{color:#444;}",
        "</style></head><body>",
        "<h1>Kindle Home</h1>",
        "<p class='muted'>Static dashboard (Phase 0 scaffold)</p>",
        "<p>Clock, device status, weather, and news will appear here.</p>",
        "</body></html>",
    })
end

function Dashboard:show()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
    self.widget = ScrollHtmlWidget:new{
        html_body = build_html(),
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
end

function Dashboard:refresh()
    self:show()
end

function Dashboard:close()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
end

return Dashboard
