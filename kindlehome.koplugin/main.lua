-- SPDX-License-Identifier: MIT
local Dispatcher = require("dispatcher")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ArticleStore = require("lib/article_store")
local Config = require("lib/config")
local Logger = require("lib/logger")
local Paths = require("lib/paths")
local Refresh = require("lib/refresh")
local Actions = require("ui/actions")
local Menus = require("ui/menus")
local Messages = require("ui/messages")

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

    -- Keep the library Markdown-only: drop legacy adjacent .md.html renders
    -- and any ephemeral HTML left by a previous session.
    UIManager:scheduleIn(1, function()
        pcall(function()
            local store = ArticleStore:new(self.paths)
            store:cleanup_legacy_html()
            store:cleanup_ephemeral_html()
        end)
    end)

    Logger.info("main", "init", { settings = self.config.settings_path })

    Dispatcher:registerAction("kindlehome_show_dashboard", {
        category = "none",
        event = "KindlehomeShowDashboard",
        title = _("Kindle Home"),
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
end

function KindleHome:addToMainMenu(menu_items)
    Menus:add_settings(menu_items, self)
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
        local notice = nil
        if dashboard.widget then
            dashboard:set_refreshing(true)
            pcall(function() UIManager:forceRePaint() end)
        elseif opts.user_initiated then
            notice = InfoMessage:new{ text = _("Refreshing…"), timeout = 8 }
            UIManager:show(notice)
            pcall(function() UIManager:forceRePaint() end)
        end
        local ok, err = pcall(function()
            dashboard:refresh({ allow_network = net_allowed, reset_page = opts.reset_page })
        end)
        if notice then
            pcall(function() UIManager:close(notice) end)
        end
        Refresh.finish()
        if not ok then
            Logger.err("main", "refresh_failed", { err = tostring(err) })
            UIManager:show(InfoMessage:new{ text = Messages.refresh_result("exception"), timeout = 4 })
            pcall(function() dashboard:show({ allow_network = false, refresh_hint = Messages.refresh_result("exception") }) end)
        end
    end

    -- Cache-first open: if user initiated while offline, prompt WiFi and fallback to cached state.
    if opts.user_initiated and not is_online() then
        local prompted = false
        local function after_prompt()
            do_refresh(is_online())
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
            pcall(function() dashboard:show({ allow_network = false, refresh_hint = Messages.for_kind("offline") }) end)
            return
        end
        UIManager:show(InfoMessage:new{ text = Messages.for_kind("offline"), timeout = 3 })
        do_refresh(false)
        return
    end

    do_refresh(allow_network)
end

function KindleHome:registerActions()
    self.actions:register("settings", function()
        local ok, err = pcall(function() Menus:show_settings(self) end)
        if ok then return end
        Logger.warn("main", "open_settings_failed", { err = tostring(err) })
        UIManager:show(InfoMessage:new{
            text = Messages.for_kind("settings_unavailable"), timeout = 4,
        })
    end)
    self.actions:register("refresh", function(ctx)
        local user_initiated = ctx and (ctx.source == "dashboard" or ctx.source == "dispatcher" or ctx.user_initiated)
        self:request_dashboard_refresh({ user_initiated = user_initiated, reset_page = user_initiated })
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
        if arg == nil or arg == "" then return end
        local d = (ctx and ctx.dashboard) or self:getDashboard()
        if type(d.open_hn_item) == "function" then
            d:open_hn_item(arg)
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
end

function KindleHome:getArticleView()
    if not self.article_view then
        local ArticleView = dofile(self.path .. "/ui/article_view.lua")
        self.article_view = ArticleView:new{
            config = self.config,
            actions = self.actions,
            on_close = function()
                self:getDashboard():show({ allow_network = false })
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
            plugin_dir = self.path,
        }
        Logger.info("main", "dashboard_created")
    end
    return self.dashboard
end

function KindleHome:onKindlehomeShowDashboard()
    -- Safe/idempotent open: Dispatcher/gesture/profile calls reuse the dashboard flow.
    -- Always paint cached state first so opening never blocks on network; the
    -- optional refresh runs afterwards, outside this paint.
    self:getDashboard():show({ allow_network = false })
    if self.config:get("refresh_on_open") then
        UIManager:scheduleIn(0.5, function()
            if Refresh.is_in_progress() then return end
            self:request_dashboard_refresh({ user_initiated = true, allow_network = is_online() })
        end)
    end
    return true
end

return KindleHome
