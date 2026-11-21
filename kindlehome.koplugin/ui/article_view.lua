local UIManager = require("ui/uimanager")
local ArticleHtmlPager = require("ui/article_html_pager")
local ReaderUI = require("apps/reader/readerui")

local Theme = require("lib/render/theme")
local MdToHtml = require("lib/render/md_to_html")
local Logger = require("lib/logger")
local Messages = require("ui/messages")
local Shell = require("ui/shell")

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
        self:_back()
        return true
    elseif uri == "kh:dashboard" then
        if self.actions then
            self.actions:dispatch("close", { source = "article_view", view = self })
            return true
        end
    elseif uri == "kh:close" then
        self:close()
        return true
    end
    Logger.warn("article_view", "unknown_link", { uri = uri })
    return false
end

local function cleanup_doc(doc)
    if doc and type(doc.on_cleanup) == "function" then
        pcall(doc.on_cleanup)
    end
end

local function build_actions(doc, view)
    local specs = {}
    if type(doc.on_back) == "function" then
        table.insert(specs, {
            icon = "chevron.left",
            label = "Back",
            callback = function() doc.on_back() end,
        })
    end
    if view.config and can_open_in_reader() and doc.html_path then
        table.insert(specs, {
            icon = "book.opened",
            label = "Reader",
            callback = function()
                local opened = view:openInReader(doc.html_path, function() cleanup_doc(doc) end)
                if not opened then cleanup_doc(doc) end
            end,
        })
    end
    table.insert(specs, {
        icon = "exit",
        label = "Close",
        callback = function() view:close() end,
    })
    return specs
end

function ArticleView:will_open_in_reader(doc)
    doc = doc or {}
    local force_fallback = self.config and type(self.config.get) == "function"
        and self.config:get("ui_force_article_fallback") == true
    return not not (doc.html_path and can_open_in_reader() and not force_fallback)
end

function ArticleView:show(doc)
    doc = doc or {}
    local previous = self.current
    if previous and previous ~= doc and previous.html_path ~= doc.html_path then
        cleanup_doc(previous)
    end
    local body = self:_resolve_body(doc)
    self.current = doc
    self:_teardown()

    local css = MdToHtml.css()
    local font_size = Theme.font_size(self.config, Theme.ARTICLE_BASE)
    local title = doc.title or (doc.meta and doc.meta.title) or "Article"

    -- Flujo por defecto: abrir el documento local persistido en el lector
    -- nativo de KOReader (ReaderUI), que ofrece selección de texto,
    -- anotaciones, progreso, diccionario y modo nocturno, todo offline.
    if self:will_open_in_reader(doc) then
        local ok, opened = pcall(function()
            return self:openInReader(doc.html_path, function() cleanup_doc(doc) end)
        end)
        if ok and opened ~= false then
            Logger.info("article_view", "opened_in_reader", { path = doc.html_path })
            return
        end
        Logger.err("article_view", "open_reader_failed_fallback", {
            path = doc.html_path,
            err = ok and "reader_returned_false" or tostring(opened),
        })
        cleanup_doc(doc)
        if type(doc.on_fallback) == "function" then
            doc.on_fallback()
        end
    end

    local shell = Shell:new{
        title = title,
        config = self.config,
        actions = build_actions(doc, self),
        on_back = function() self:_back() end,
        on_layout_change = function() self:show(doc) end,
        on_close = function() self:_closed_by_user() end,
        body_factory = function(width, height)
            return ArticleHtmlPager:new{
                width = width,
                height = height,
                body = body,
                css = css,
                font_size = font_size,
                on_link = function(link)
                    self:handle_link(link and link.uri)
                end,
            }
        end,
    }
    self.widget = shell
    shell:show()
    Logger.info("article_view", "shown", { title = title })
end

function ArticleView:_back()
    local doc = self.current or {}
    cleanup_doc(doc)
    self:_teardown()
    if type(doc.on_back) == "function" then
        doc.on_back()
        return
    end
    if self.on_close then
        pcall(self.on_close)
    end
end

function ArticleView:_closed_by_user()
    cleanup_doc(self.current)
    self.widget = nil
    if self.on_close then
        pcall(self.on_close)
    end
end

function ArticleView:_teardown()
    local widget = self.widget
    if not widget then return end
    self.widget = nil
    widget._closing = true
    widget.on_close = nil
    widget.on_back = nil
    pcall(function() UIManager:close(widget) end)
end

function ArticleView:openInReader(path, on_close)
    if not path or not can_open_in_reader() then
        Logger.warn("article_view", "open_reader_unavailable", { path = path })
        return false
    end
    local function hook_close(reader)
        if type(reader) ~= "table" or reader._kindlehome_html_hook then return end
        reader._kindlehome_html_hook = true
        local original = reader.onCloseWidget
        reader.onCloseWidget = function(self, ...)
            if self._kindlehome_html_hook then
                self._kindlehome_html_hook = nil
                if type(on_close) == "function" then pcall(on_close) end
            end
            if type(original) == "function" then
                return original(self, ...)
            end
        end
    end
    -- Optional, isolated flow: ReaderUI manages its own lifecycle/return behavior.
    -- The after-open callback receives the reader instance; hooking its close
    -- removes the ephemeral HTML as soon as the reader goes away.
    local ok, err = pcall(function()
        ReaderUI:showReader(path, nil, nil, nil, hook_close)
    end)
    if not ok then
        Logger.err("article_view", "open_reader_failed", { err = tostring(err) })
        return false
    end
    Logger.info("article_view", "open_reader", { path = path })
    return true
end

function ArticleView:close()
    cleanup_doc(self.current)
    self:_teardown()
    if self.on_close then
        pcall(self.on_close)
    end
    Logger.info("article_view", "closed")
end

return ArticleView
