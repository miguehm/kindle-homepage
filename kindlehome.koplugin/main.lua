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
local Digest = require("lib/digest")
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
        if opts.user_initiated then
            UIManager:show(InfoMessage:new{ text = _("Refreshing…"), timeout = 1 })
        end
        local ok = pcall(function()
            dashboard:refresh({ allow_network = net_allowed })
        end)
        Refresh.finish()
        if not ok then
            Logger.err("main", "refresh_failed")
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
    self.actions:register("refresh", function(ctx)
        local user_initiated = ctx and (ctx.source == "dashboard" or ctx.source == "dispatcher" or ctx.user_initiated)
        self:request_dashboard_refresh({ user_initiated = user_initiated })
    end)
    self.actions:register("generate_digest", function(ctx)
        local dash = (ctx and ctx.dashboard) or self:getDashboard()
        local state = dash and (dash.last_state or dash:build_state({ allow_network = false }))
        local doc, err = Digest.build_and_save(state or {}, self.paths)
        if not doc then
            UIManager:show(InfoMessage:new{ text = _("Could not save digest."), timeout = 3 })
            Logger.err("main", "digest_generate_failed")
            return
        end
        UIManager:show(InfoMessage:new{ text = _("Digest saved."), timeout = 2 })
        if self.actions then
            self.actions:dispatch("open_digest", { dashboard = dash, source = "action" }, "open_digest:" .. tostring(doc.date or "latest"), tostring(doc.date or "latest"))
        end
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
        local which = arg
        if which == nil or which == "" then which = "latest" end
        local doc, err = Digest.load(self.paths, which)
        if not doc then
            -- try to generate today's digest from cached dashboard state when opening latest
            if which == "latest" then
                local dash = (ctx and ctx.dashboard) or self:getDashboard()
                local state = dash and (dash.last_state or dash:build_state({ allow_network = false }))
                if state then
                    local generated, gerr = Digest.build_and_save(state, self.paths)
                    if generated then
                        doc = generated
                        err = nil
                    else
                        err = gerr or err
                    end
                end
            end
        end
        if not doc then
            if self.article_view then
                self.article_view:show({
                    title = "Digest unavailable",
                    status = (err == "not_found" and "not_found") or "content_unavailable",
                    meta = { id = tostring(which), status = tostring(err or "not_found"), source = "digest" },
                })
            end
            return
        end
        local dash = (ctx and ctx.dashboard) or self:getDashboard()
        if dash and dash.widget then
            UIManager:close(dash.widget)
            dash.widget = nil
        end
        self:getArticleView():show(doc)
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
    -- Safe/idempotent open: Dispatcher/gesture/profile calls reuse dashboard flow.
    if self.config:get("refresh_on_open") then
        self:request_dashboard_refresh({ user_initiated = true, allow_network = is_online() })
    else
        self:getDashboard():show({ allow_network = false })
    end
    return true
end

return KindleHome
