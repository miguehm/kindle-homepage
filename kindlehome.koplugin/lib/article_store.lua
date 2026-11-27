-- SPDX-License-Identifier: MIT
local lfs = require("libs/libkoreader-lfs")
local MdToHtml = require("lib/render/md_to_html")
local Hnmd = require("lib/hnmd")
local Logger = require("lib/logger")

local ArticleStore = {}
ArticleStore.__index = ArticleStore

local function ensure_dir(paths, dir)
    if paths and paths.ensure_dir then
        return paths:ensure_dir(dir)
    end
    return false
end

local function file_exists(path)
    local ok, attr = pcall(lfs.attributes, path)
    return ok and attr and attr.mode == "file"
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function build_frontmatter(meta)
    local keys = { "id", "title", "source", "date", "status", "hn_url", "url" }
    local lines = { "---" }
    for _, k in ipairs(keys) do
        local v = meta and meta[k]
        if v ~= nil and v ~= "" then
            local s = tostring(v):gsub("\n", " "):gsub('"', '\\"')
            table.insert(lines, string.format('%s: "%s"', k, s))
        end
    end
    table.insert(lines, "---")
    table.insert(lines, "")
    return table.concat(lines, "\n")
end

function ArticleStore:new(paths)
    return setmetatable({ paths = paths }, self)
end

function ArticleStore:_dir_for(kind)
    return self.paths:articles_hn_dir()
end

function ArticleStore:_base_name(kind, meta)
    local id = meta and meta.id and tostring(meta.id) or tostring(os.time())
    local title = (meta and meta.title) or ("hn-" .. id)
    return self.paths:safe_filename(title, nil, "hn-" .. id)
end

function ArticleStore:paths_for(kind, meta)
    local dir = self:_dir_for(kind)
    local base = self:_base_name(kind, meta)
    local md = dir .. "/" .. base .. ".md"
    return {
        dir = dir,
        base = base,
        md = md,
        html = self.paths:article_html_path(md),
    }
end

function ArticleStore:save(opts)
    opts = opts or {}
    local kind = opts.kind or "hn"
    local meta = opts.meta or {}
    local md_body = tostring(opts.md or "")
    local paths = self:paths_for(kind, meta)
    ensure_dir(self.paths, paths.dir)
    local md_target = opts.md_path or paths.md
    local html_target = opts.html_path or paths.html

    local md_content = build_frontmatter(meta) .. md_body
    local body_html = opts.body_html or MdToHtml.render(md_body)
    local md_has_heading = md_body:match("^%s*#%s") ~= nil
    local html_content = MdToHtml.document({
        title = meta.title or "Article",
        meta = meta,
        body_html = body_html,
        show_title = not md_has_heading,
    })

    local ok1, err1 = self.paths:atomic_write(md_target, md_content)
    if not ok1 then
        Logger.err("article_store", "save_md_failed", { path = md_target, reason = err1 })
        return nil, err1
    end
    self:_remove_legacy_html(md_target, html_target)
    local ok2, err2 = self.paths:atomic_write(html_target, html_content)
    if not ok2 then
        Logger.err("article_store", "save_html_failed", { path = html_target, reason = err2 })
        return { md_path = md_target, html_path = nil, meta = meta, body_html = body_html }, err2
    end
    Logger.info("article_store", "saved", { kind = kind, md = md_target })
    return {
        md_path = md_target,
        html_path = html_target,
        meta = meta,
        body_html = body_html,
        html = html_content,
    }
end

local function safe_article_href(url)
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$") or ""
    if url == "" or not url:lower():match("^https?://") then return nil end
    return MdToHtml.escape(url)
end

function ArticleStore:save_link_card(item, meta, reason)
    item = item or {}
    meta = meta or {}
    local md_path = self.paths and type(self.paths.article_link_path) == "function"
        and self.paths:article_link_path(item) or nil
    if not md_path then return nil, "invalid_item" end
    local html_path = self.paths:article_html_path(md_path)
    local id = tostring(meta.id or item.id or "")
    local title = tostring(meta.title or item.title or "HN article")
    local hn_url = meta.hn_url
    if not hn_url or hn_url == "" then
        hn_url = "https://news.ycombinator.com/item?id=" .. id
    end
    local source_url = meta.url

    local body = {
        "<p>This article could not be downloaded. Copy one of these links and open it manually.</p>",
        "<ul>",
    }
    local function link_line(label, url)
        local safe = safe_article_href(url)
        if safe then
            table.insert(body, "<li>" .. label .. ': <a href="' .. safe .. '">'
                .. MdToHtml.escape(url) .. "</a></li>")
        else
            table.insert(body, "<li>" .. label .. ": " .. MdToHtml.escape(url or "") .. "</li>")
        end
    end
    link_line("HN discussion", hn_url)
    if source_url and source_url ~= "" then
        link_line("Source", source_url)
    else
        table.insert(body, "<li>Source: Ask HN (no source URL)</li>")
    end
    if reason and reason ~= "" then
        table.insert(body, "<li>Reason: " .. MdToHtml.escape(tostring(reason)) .. "</li>")
    end
    table.insert(body, "</ul>")

    local md_lines = {
        "# " .. title,
        "",
        "This article could not be downloaded. Copy one of these links and open it manually.",
        "",
        "- HN discussion: " .. tostring(hn_url),
    }
    if source_url and source_url ~= "" then
        table.insert(md_lines, "- Source: " .. tostring(source_url))
    else
        table.insert(md_lines, "- Source: Ask HN (no source URL)")
    end
    if reason and reason ~= "" then
        table.insert(md_lines, "- Reason: " .. tostring(reason))
    end

    local card_meta = {
        id = id,
        title = title,
        source = "kindlehome:hn-link",
        date = meta.date,
        status = "link_card",
        hn_url = hn_url,
        url = source_url,
    }
    return self:save({
        kind = "hn",
        meta = card_meta,
        md = table.concat(md_lines, "\n") .. "\n",
        body_html = table.concat(body, "\n"),
        md_path = md_path,
        html_path = html_path,
    })
end

local function file_non_empty(path)
    if not file_exists(path) then return false end
    local f = io.open(path, "rb")
    if not f then return false end
    local chunk = f:read(1)
    f:close()
    return chunk ~= nil and chunk ~= ""
end

local function mtime(path)
    local ok, attr = pcall(lfs.attributes, path)
    if ok and type(attr) == "table" then
        return tonumber(attr.modification) or 0
    end
    return 0
end

-- `current_only`: the file was rendered with today's marker (safe to reuse).
-- Otherwise any marker version proves the file is plugin-generated.
local function has_render_marker(path, current_only)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(512)
    f:close()
    if current_only then
        return head ~= nil and head:find(MdToHtml.render_marker(), 1, true) ~= nil
    end
    return MdToHtml.is_generated(head)
end

-- Removes the old derived "<file>.md.html" that lived next to the canonical
-- Markdown. Only plugin-generated files (with the render marker) are touched.
function ArticleStore:_remove_legacy_html(md_path, html_path)
    if type(md_path) ~= "string" or md_path == "" then return end
    local legacy = md_path .. ".html"
    if legacy == html_path then return end
    if file_exists(legacy) and has_render_marker(legacy) then
        if os.remove(legacy) then -- ephemeral cleanup: derived HTML only
            Logger.info("article_store", "legacy_html_removed", { path = legacy })
        end
    end
end

-- Deletes the ephemeral HTML rendered for ReaderUI/the fallback pager.
function ArticleStore:remove_ephemeral(html_path)
    if type(html_path) ~= "string" or html_path == "" then return false end
    local ok = os.remove(html_path) -- ephemeral cleanup: derived HTML only
    if ok then
        Logger.info("article_store", "ephemeral_html_removed", { path = html_path })
    end
    return ok and true or false
end

local function cleanup_html_dir(dir, pattern)
    if type(dir) ~= "string" or dir == "" then return 0 end
    local ok_dir, iter, state = pcall(lfs.dir, dir)
    if not ok_dir or type(iter) ~= "function" then return 0 end
    local removed = 0
    for name in iter, state do
        if type(name) == "string" and name:match(pattern) then
            local path = dir .. "/" .. name
            if pattern == "%.md%.html$" and not has_render_marker(path) then
                -- Keep user files that merely share the extension.
            elseif os.remove(path) then -- ephemeral cleanup: derived HTML only
                removed = removed + 1
            end
        end
    end
    return removed
end

-- One-time migration: drop legacy .md.html files from the content folder.
function ArticleStore:cleanup_legacy_html()
    local removed = cleanup_html_dir(self.paths:articles_hn_dir(), "%.md%.html$")
    if removed > 0 then
        Logger.info("article_store", "legacy_html_cleanup", { removed = removed })
    end
    return removed
end

-- Startup cleanup: no ephemeral HTML should survive a plugin reload.
function ArticleStore:cleanup_ephemeral_html()
    local dir = self.paths.ephemeral_articles_dir and self.paths:ephemeral_articles_dir() or nil
    local removed = cleanup_html_dir(dir, "%.html$")
    if removed > 0 then
        Logger.info("article_store", "ephemeral_html_cleanup", { removed = removed })
    end
    return removed
end

-- Old generated .md files carry our YAML frontmatter; downloaded ones are raw
-- Markdown. Strip only a frontmatter-looking block so a leading "---" (hr) in
-- real content is preserved.
local function strip_frontmatter(md)
    if md:sub(1, 3) ~= "---" then return md end
    local block, rest = md:match("^%-%-%-\r?\n(.-)\r?\n%-%-%-%s*\r?\n(.*)$")
    if block and block:find("^%s*%w[%w_]*:%s") then
        return rest
    end
    return md
end

function ArticleStore:is_local(md_path)
    return file_non_empty(md_path)
end

-- Builds the ephemeral HTML under the cache (or reuses it when the .md has not
-- changed). Returns the HTML path so callers can hand it to KOReader's native
-- reader; the caller is responsible for deleting it when done.
function ArticleStore:render_derived(md_path, meta, force)
    if not file_non_empty(md_path) then
        return nil, "not_found"
    end
    local html_path = self.paths:article_html_path(md_path)
    if not html_path then
        return nil, "missing_path"
    end
    self:_remove_legacy_html(md_path, html_path)
    if not force and file_non_empty(html_path) and mtime(html_path) >= mtime(md_path)
            and has_render_marker(html_path, true) then
        return html_path
    end

    local md, read_err = self:load_md(md_path)
    if not md then
        return nil, read_err or "read_failed"
    end
    local body_md = strip_frontmatter(md)
    local title = meta and meta.title
    if not title or title == "" then
        title = body_md:match("^%s*#%s+(.+)") or "Article"
    end
    local body_html = MdToHtml.render(body_md)
    local html = MdToHtml.document({
        title = title,
        meta = meta or {},
        body_html = body_html,
        show_title = body_md:match("^%s*#%s") == nil,
    })
    local ok, werr = self.paths:atomic_write(html_path, html)
    if not ok then
        Logger.warn("article_store", "render_failed", { path = html_path, reason = werr })
        return nil, werr
    end
    return html_path
end

-- Makes the article available on disk as Markdown, downloading it only when
-- the local copy is missing/empty. A 404 or network failure never deletes an
-- existing local copy (stale is better than nothing).
function ArticleStore:ensure_local(config, item, opts)
    opts = opts or {}
    if type(item) ~= "table" or not item.id then
        return { ok = false, error_kind = "parse", error = "invalid_item" }
    end
    if item.content_status and item.content_status ~= "ok" then
        return { ok = false, error_kind = item.content_status, error = item.content_error }
    end

    local md_path = opts.md_path or self.paths:article_md_path(item)
    local dir = self.paths:articles_hn_dir()
    ensure_dir(self.paths, dir)

    local had_local = file_non_empty(md_path)
    if opts.force or not had_local then
        local tmp = md_path .. ".tmp"
        local dl = Hnmd.download_article(config, item, tmp, {
            timeout_s = config and config:get("http_timeout_s"),
            max_bytes = config and config:get("article_max_bytes"),
        })
        if not dl.ok then
            pcall(os.remove, tmp)
            local stale = file_non_empty(md_path)
            Logger.warn("article_store", "download_failed", {
                id = item.id, kind = dl.error_kind, kept_stale = stale,
            })
            return {
                ok = false,
                error_kind = dl.error_kind,
                error = dl.error,
                status = dl.status,
                md_path = stale and md_path or nil,
                stale = stale,
            }
        end
        local ok_rename, rename_err = os.rename(tmp, md_path)
        if not ok_rename then
            pcall(os.remove, tmp)
            Logger.err("article_store", "promote_failed", { path = md_path, reason = rename_err })
            return {
                ok = false,
                error_kind = "network",
                error = "rename_failed",
                md_path = file_non_empty(md_path) and md_path or nil,
            }
        end
    end

    local html_path, rerr = self:render_derived(md_path, item, opts.force)
    if not html_path then
        -- The .md is what matters; let the caller fall back to plain text.
        return { ok = true, md_path = md_path, html_path = nil, render_error = rerr }
    end
    return { ok = true, md_path = md_path, html_path = html_path }
end

function ArticleStore:load_html(path)
    if type(path) ~= "string" or path == "" then
        return nil, "missing_path"
    end
    if not file_exists(path) then
        return nil, "not_found"
    end
    local content = read_file(path)
    if not content or content == "" then
        return nil, "corrupted_file"
    end
    return content
end

function ArticleStore:load_md(path)
    if type(path) ~= "string" or path == "" then
        return nil, "missing_path"
    end
    if not file_exists(path) then
        return nil, "not_found"
    end
    local content = read_file(path)
    if not content or content == "" then
        return nil, "corrupted_file"
    end
    return content
end

return ArticleStore
