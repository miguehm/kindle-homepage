local Device = require("device")
local UIManager = require("ui/uimanager")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen

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
    return MdToHtml.document_body({
        title = "Kindle Home",
        show_title = true,
        body_html = MdToHtml.notice_html(msg),
    })
end

function ArticleView:_resolve_body(doc)
    doc = doc or {}
    local md = doc.md
    local meta = doc.meta or {}
    if md == nil or md == "" then
        if type(doc.body_html) == "string" and doc.body_html ~= "" then
            return MdToHtml.document_body({
                title = meta.title or doc.title or "Article",
                meta = meta,
                body_html = doc.body_html,
            })
        end
        if type(doc.html) == "string" and doc.html ~= "" then
            -- Persisted standalone document without markdown: render as-is.
            return doc.html
        end
        return self:_build_state_error(doc.status or "no_markdown")
    end
    local ok, body = pcall(MdToHtml.document_body, {
        title = meta.title or doc.title or "Article",
        meta = meta,
        md = md,
        show_title = true,
    })
    if not ok then
        Logger.err("article_view", "render_failed", { err = tostring(body) })
        return self:_build_state_error("render_error")
    end
    return body
end

function ArticleView:handle_link(uri)
    uri = tostring(uri or "")
    if uri == "kh:back" then
        local doc = self.current or {}
        if type(doc.on_back) == "function" then
            doc.on_back()
            return true
        end
    elseif uri == "kh:dashboard" then
        if self.actions then
            self.actions:dispatch("close", { source = "article_view", view = self })
            return true
        end
    elseif uri == "kh:reader" then
        local doc = self.current or {}
        if doc.html_path then
            self:openInReader(doc.html_path)
            return true
        end
    elseif uri == "kh:close" then
        self:close()
        return true
    end
    Logger.warn("article_view", "unknown_link", { uri = uri })
    return false
end

function ArticleView:show(doc)
    doc = doc or {}
    local body = self:_resolve_body(doc)
    self.current = doc

    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    -- Navigation as links: ScrollHtmlWidget has no buttons, but link taps go
    -- through html_link_tapped_callback (kh:* scheme).
    local nav = { "<div class='nav'><b>Navigation</b>" }
    if type(doc.on_back) == "function" then
        table.insert(nav, "<div class='navitem'><a href='kh:back'>Back</a></div>")
    end
    if self.actions then
        table.insert(nav, "<div class='navitem'><a href='kh:dashboard'>Dashboard</a></div>")
    end
    if self.config and self.config:get("open_in_reader_enabled") and can_open_in_reader() and doc.html_path then
        table.insert(nav, "<div class='navitem'><a href='kh:reader'>Open in reader</a></div>")
    end
    table.insert(nav, "<div class='navitem'><a href='kh:close'>Close</a></div>")
    table.insert(nav, "</div>")

    local widget = ScrollHtmlWidget:new{
        html_body = body .. table.concat(nav),
        css = MdToHtml.css() .. ".nav{margin:24px 0 0 0;padding-top:12px;border-top:2px solid #333;font-size:17px;}"
            .. ".navitem{font-size:19px;margin:12px 0;}",
        default_font_size = Screen:scaleBySize(20),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        html_link_tapped_callback = function(link)
            self:handle_link(link and link.uri)
        end,
    }
    -- Required: ScrollHtmlWidget scroll handlers touch self.dialog.movable and
    -- pass dialog to UIManager:setDirty (nil raises "attempt to index 'dialog'").
    widget.dialog = widget
    self.widget = widget
    UIManager:show(widget)
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
