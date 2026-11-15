local lfs = require("libs/libkoreader-lfs")
local MdToHtml = require("lib/render/md_to_html")
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
    local html_content = MdToHtml.document({
        title = meta.title or "Article",
        meta = meta,
        body_html = body_html,
        show_title = true,
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
