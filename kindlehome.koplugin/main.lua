local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local KindleHome = WidgetContainer:extend{
    name = "kindlehome",
    is_doc_only = false,
}

function KindleHome:init()
    Dispatcher:registerAction("kindlehome_show_dashboard", {
        category = "none",
        event = "KindlehomeShowDashboard",
        title = _("Kindle Home"),
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
end

function KindleHome:addToMainMenu(menu_items)
    menu_items.kindlehome = {
        text = _("Kindle Home"),
        sorting_hint = "tools",
        callback = function()
            self:onKindlehomeShowDashboard()
        end,
    }
end

function KindleHome:getDashboard()
    if not self.dashboard then
        local Dashboard = dofile(self.path .. "/ui/dashboard.lua")
        self.dashboard = Dashboard:new()
    end
    return self.dashboard
end

function KindleHome:onKindlehomeShowDashboard()
    self:getDashboard():show()
    return true
end

return KindleHome
