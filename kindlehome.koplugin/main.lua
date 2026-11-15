local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Config = require("lib/config")
local Logger = require("lib/logger")
local Paths = require("lib/paths")
local Refresh = require("lib/refresh")
local Actions = require("ui/actions")
local Menus = require("ui/menus")

local KindleHome = WidgetContainer:extend{
    name = "kindlehome",
    is_doc_only = false,
}

function KindleHome:init()
    self.config = Config:new()
    self.paths = Paths:new(self.config)
    self.paths:ensure_base_dirs()
    self.actions = Actions:new{ config = self.config }
    self:registerActions()

    Logger.info("main", "init", { settings = self.config.settings_path })

    Dispatcher:registerAction("kindlehome_show_dashboard", {
        category = "none",
        event = "KindlehomeShowDashboard",
        title = _("Kindle Home"),
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
    -- minimal settings menu (Phase 4 weather fields); safe if menu system differs
    pcall(Menus.register, Menus, self)
end

function KindleHome:addToMainMenu(menu_items)
    -- Fallback registration for KOReader menu structures that expect this method.
    menu_items.kindlehome = menu_items.kindlehome or {
        text = _("Kindle Home"),
        sorting_hint = "tools",
        callback = function() self:onKindlehomeShowDashboard() end,
    }
    if menu_items.kindlehome_settings then
        menu_items.kindlehome_settings = menu_items.kindlehome_settings
    end
end

local function is_online()
    local ok, connected = pcall(function() return NetworkMgr:isConnected() end)
    return ok and connected and true or false
end

function KindleHome:request_dashboard_refresh(opts)
    opts = opts or {}
    local dashboard = self:getDashboard()

    if Refresh.is_in_progress() then
        UIManager:show(InfoMessage:new{ text = _("Refresh already in progress."), timeout = 2 })
        Logger.info("main", "refresh_reentry_blocked")
        return
    end

    local allow_network = opts.allow_network
    if allow_network == nil then
        allow_network = is_online()
    end

    local function do_refresh(net_allowed)
        if not Refresh.begin() then
            UIManager:show(InfoMessage:new{ text = _("Refresh already in progress."), timeout = 2 })
            return
        end
        local ok, err = pcall(function()
            dashboard:refresh({ allow_network = net_allowed })
        end)
        Refresh.finish()
        if not ok then
            Logger.err("main", "refresh_failed", { err = tostring(err) })
            UIManager:show(InfoMessage:new{ text = _("Refresh failed. Showing cached data if available."), timeout = 4 })
            pcall(function() dashboard:show({ allow_network = false }) end)
        end
    end

    -- If network is needed but unavailable, prompt WiFi and refresh after callback, always fallback to cache.
    if opts.user_initiated and not is_online() then
        local prompted = false
        local function after_prompt()
            local net = is_online()
            do_refresh(net)
        end
        local ok_prompt = pcall(function()
            if NetworkMgr.promptWifiOn then
                NetworkMgr:promptWifiOn(after_prompt)
                prompted = true
            elseif NetworkMgr.runWhenOnline then
                NetworkMgr:runWhenOnline(after_prompt)
                prompted = true
            end
        end)
        if ok_prompt and prompted then
            -- Also show cached state immediately so UI is responsive.
            pcall(function() dashboard:show({ allow_network = false, refresh_hint = "wifi_prompt" }) end)
            return
        end
        -- No prompt available: cache-only fallback with brief message.
        UIManager:show(InfoMessage:new{ text = _("Offline. Turn on WiFi and refresh."), timeout = 3 })
        do_refresh(false)
        return
    end

    do_refresh(allow_network)
end

function KindleHome:registerActions()
    self.actions:register("refresh", function(ctx)
        local user_initiated = ctx and (ctx.source == "dashboard" or ctx.source == "dispatcher" or ctx.user_initiated)
        self:request_dashboard_refresh({ user_initiated = user_initiated })
    end)
    self.actions:register("close", function(ctx)
        local src = ctx and ctx.source
        if src == "article_view" and self.article_view then
            self.article_view:close()
            self:getDashboard():show({ allow_network = false })
            return
        end
        self:getDashboard():close()
    end)
    self.actions:register("open_hn", function(ctx, _, arg)
        local d = (ctx and ctx.dashboard) or self:getDashboard()
        if arg == nil or arg == "" then
            d:open_test_article()
            return
        end
        if type(d.open_hn_item) == "function" then
            d:open_hn_item(arg)
            return
        end
        if arg == "test-phase3" then
            d:open_test_article()
            return
        end
        if self.article_view then
            self.article_view:show({
                title = "Article unavailable",
                status = "not_found",
                meta = { id = arg, status = "not_found", source = "hn" },
            })
        end
    end)
    self.actions:register("open_digest", function(ctx, _, arg)
        if self.article_view then
            self.article_view:show({
                title = "Digest unavailable",
                status = "not_found",
                meta = { id = arg or "", status = "not_found", source = "digest" },
            })
        end
    end)
end

function KindleHome:getArticleView()
    if not self.article_view then
        local ArticleView = dofile(self.path .. "/ui/article_view.lua")
        self.article_view = ArticleView:new{
            config = self.config,
            actions = self.actions,
            on_close = function()
                -- return path is controlled by actions/caller
            end,
        }
    end
    return self.article_view
end

function KindleHome:getDashboard()
    if not self.dashboard then
        local Dashboard = dofile(self.path .. "/ui/dashboard.lua")
        self.dashboard = Dashboard:new{
            config = self.config,
            paths = self.paths,
            actions = self.actions,
            article_view = self:getArticleView(),
        }
        Logger.info("main", "dashboard_created")
    end
    return self.dashboard
end

function KindleHome:onKindlehomeShowDashboard()
    if self.config:get("refresh_on_open") then
        self:request_dashboard_refresh({ user_initiated = true, allow_network = is_online() })
    else
        self:getDashboard():show({ allow_network = false })
    end
    return true
end

return KindleHome
