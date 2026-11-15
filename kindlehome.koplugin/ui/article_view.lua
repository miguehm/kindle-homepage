local Device = require("device")
local UIManager = require("ui/uimanager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local _ = require("gettext")

local MdToHtml = require("lib/render/md_to_html")
local Logger = require("lib/logger")
local Messages = require("ui/messages")

local ArticleView = {}

function ArticleView:new(opts)
    opts = opts or {}
    local o = {
        config = opts.config,
        actions = opts.actions,
        widget = nil,
        on_close = opts.on_close,
        current = nil,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

local function can_open_in_reader()
    return ReaderUI and type(ReaderUI.showReader) == "function"
end

function ArticleView:_build_state_error(kind)
    local msg = Messages.reading(kind)
    if kind == "missing_path" then msg = "Content path is missing." end
    if kind == "render_error" then msg = "Content unavailable." end
    return MdToHtml.document({
        title = "Kindle Home",
        show_title = true,
        body_html = MdToHtml.notice_html(msg),
    })
end

function ArticleView:_resolve_html(doc)
    doc = doc or {}
    local md = doc.md
    local meta = doc.meta or {}
    if type(doc.html) == "string" and doc.html ~= "" then
        return doc.html
    end
    if md == nil or md == "" then
        local st = doc.status or "no_markdown"
        return self:_build_state_error(st)
    end
    local ok, html = pcall(MdToHtml.document, {
        title = meta.title or doc.title or "Article",
        meta = meta,
        md = md,
        show_title = true,
    })
    if not ok then
        Logger.err("article_view", "render_failed", { err = tostring(html) })
        return self:_build_state_error("render_error")
    end
    return html
end

function ArticleView:show(doc)
    doc = doc or {}
    local html = self:_resolve_html(doc)
    self.current = doc

    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    local actions = {}
    if doc.on_back then
        table.insert(actions, { text = _("Back"), callback = function() doc.on_back() end })
    end
    if self.actions then
        table.insert(actions, {
            text = _("Dashboard"),
            callback = function()
                self.actions:dispatch("close", { source = "article_view", view = self })
            end,
        })
    end
    if self.config and self.config:get("open_in_reader_enabled") and can_open_in_reader() and doc.html_path then
        table.insert(actions, {
            text = _("Open in reader"),
            callback = function()
                self:openInReader(doc.html_path)
            end,
        })
    end
    table.insert(actions, {
        text = _("Close"),
        callback = function()
            self:close()
        end,
    })

    self.widget = ScrollHtmlWidget:new{
        html_body = html,
        css = "",
        default_font_size = Screen:scaleBySize(20),
        title = _(doc.title or (doc.meta and doc.meta.title) or "Article"),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        actions = actions,
    }
    UIManager:show(self.widget)
    Logger.info("article_view", "shown", { title = doc.title or (doc.meta and doc.meta.title) })
end

function ArticleView:openInReader(path)
    if not path or not can_open_in_reader() then
        Logger.warn("article_view", "open_reader_unavailable", { path = path })
        return false
    end
    -- Optional, isolated flow: ReaderUI manages its own lifecycle/return behavior.
    local ok, err = pcall(function()
        ReaderUI:showReader(path)
    end)
    if not ok then
        Logger.err("article_view", "open_reader_failed", { err = tostring(err) })
        return false
    end
    Logger.info("article_view", "open_reader", { path = path })
    return true
end

function ArticleView:close()
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end
    if self.on_close then
        pcall(self.on_close)
    end
    Logger.info("article_view", "closed")
end

return ArticleView
