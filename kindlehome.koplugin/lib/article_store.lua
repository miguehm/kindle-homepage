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
    if kind == "digest" then
        return self.paths:digest_dir()
    end
    return self.paths:articles_hn_dir()
end

function ArticleStore:_base_name(kind, meta)
    if kind == "digest" then
        local date = (meta and meta.date) or os.date("%Y-%m-%d")
        date = tostring(date)
        if date:match("^%d%d%d%d%-%d%d%-%d%d$") then
            return date
        end
        return "digest-" .. date
    end
    local id = meta and meta.id and tostring(meta.id) or tostring(os.time())
    local title = (meta and meta.title) or ("hn-" .. id)
    return self.paths:safe_filename(title, nil, "hn-" .. id)
end

function ArticleStore:paths_for(kind, meta)
    local dir = self:_dir_for(kind)
    local base = self:_base_name(kind, meta)
    return {
        dir = dir,
        base = base,
        md = dir .. "/" .. base .. ".md",
        html = dir .. "/" .. base .. ".html",
    }
end

function ArticleStore:save(opts)
    opts = opts or {}
    local kind = opts.kind or "hn"
    local meta = opts.meta or {}
    local md_body = tostring(opts.md or "")
    local paths = self:paths_for(kind, meta)
    ensure_dir(self.paths, paths.dir)

    local md_content = build_frontmatter(meta) .. md_body
    local body_html = opts.body_html or MdToHtml.render(md_body)
    local md_has_heading = md_body:match("^%s*#%s") ~= nil
    local html_content = MdToHtml.document({
        title = meta.title or "Article",
        meta = meta,
        body_html = body_html,
        show_title = not md_has_heading,
    })

    local ok1, err1 = self.paths:atomic_write(paths.md, md_content)
    if not ok1 then
        Logger.err("article_store", "save_md_failed", { path = paths.md, reason = err1 })
        return nil, err1
    end
    local ok2, err2 = self.paths:atomic_write(paths.html, html_content)
    if not ok2 then
        Logger.err("article_store", "save_html_failed", { path = paths.html, reason = err2 })
        return { md_path = paths.md, html_path = nil, meta = meta, body_html = body_html }, err2
    end
    Logger.info("article_store", "saved", { kind = kind, md = paths.md })
    return {
        md_path = paths.md,
        html_path = paths.html,
        meta = meta,
        body_html = body_html,
        html = html_content,
    }
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

-- Builds "<file>.md.html" (or refreshes it when the .md changed). Returns the
-- HTML path so callers can hand it to KOReader's native reader.
function ArticleStore:render_derived(md_path, meta, force)
    if not file_non_empty(md_path) then
        return nil, "not_found"
    end
    local html_path = self.paths:article_html_path(md_path)
    if not html_path then
        return nil, "missing_path"
    end
    if not force and file_non_empty(html_path) and mtime(html_path) >= mtime(md_path) then
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
