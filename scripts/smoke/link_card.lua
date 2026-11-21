-- SPDX-License-Identifier: MIT
-- Smoke test: fallback link cards and derived-HTML migration for link meta.
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        err = function() end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path)
            local f = io.open(path, "rb")
            if not f then return nil end
            f:close()
            return { mode = "file", modification = 0 }
        end,
    }
end
package.preload["lib/hnmd"] = function()
    return {
        download_article = function()
            return { ok = false, error_kind = "stub" }
        end,
    }
end

local Store = dofile(PLUGIN .. "lib/article_store.lua")

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")

local P = {}
function P:articles_hn_dir() return dir end
function P:ensure_dir() return true end
function P:cache_dir() return dir .. "/cache" end
function P:ephemeral_articles_dir() return self:cache_dir() .. "/articles" end
function P:article_html_path(md)
    return self:ephemeral_articles_dir() .. "/" .. tostring(md:match("([^/]+)$")) .. ".html"
end
function P:article_md_path(item)
    local slug = tostring(item.title or "article"):lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    return dir .. "/" .. tostring(item.id) .. "-" .. slug .. ".md"
end
function P:article_link_path(item)
    return (self:article_md_path(item):gsub("%.md$", "-links.md"))
end
function P:safe_filename(name, _, disambiguator)
    return tostring(name):lower():gsub("%s+", "-") .. "-" .. tostring(disambiguator)
end
function P:atomic_write(path, content)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then os.execute("mkdir -p '" .. parent .. "'") end
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
    return true
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local store = Store:new(P)
local item = { id = "123", title = "Card test", content_status = "no_content" }
local meta = { id = "123", title = "Card test", hn_url = "", url = nil, content_status = "no_content" }

local saved, err = store:save_link_card(item, meta, "no_content")
assert(saved, "link card must be written: " .. tostring(err))
assert(saved.md_path == P:article_link_path(item), "link card must use its own path")
assert(saved.html_path ~= saved.md_path .. ".html", "link card html must be ephemeral, not adjacent")
assert(saved.html_path:sub(1, #P:ephemeral_articles_dir() + 1) == P:ephemeral_articles_dir() .. "/",
    "link card html must live under the cache")
assert(read(saved.md_path .. ".html") == nil, "link card must not leave html next to its md")
local md = read(saved.md_path)
assert(md and md:find("HN discussion: https://news.ycombinator.com/item?id=123", 1, true),
    "missing fallback HN URL")
assert(md:find("Ask HN (no source URL)", 1, true), "missing Ask HN note")
assert(md:find("Reason: no_content", 1, true), "missing failure reason")
local html = read(saved.html_path)
assert(html:find('<a href="https://news.ycombinator.com/item?id=123">', 1, true),
    "fallback HN URL must be a real link")
assert(html:find("This article could not be downloaded", 1, true), "instruction missing")
assert(read(P:article_md_path(item)) == nil, "link card must not create the canonical .md")

local item2 = { id = "456", title = "With source", content_status = "http_404" }
local meta2 = {
    id = "456", title = "With source",
    hn_url = "https://news.ycombinator.com/item?id=456",
    url = "https://example.com/story",
    content_status = "http_404",
}
local saved2 = assert(store:save_link_card(item2, meta2, "http_404"))
local html2 = read(saved2.html_path)
assert(html2:find('<a href="https://news.ycombinator.com/item?id=456">', 1, true), "HN link missing")
assert(html2:find('<a href="https://example.com/story">', 1, true), "source link missing")

local canonical = P:article_md_path(item)
P:atomic_write(canonical, "# Real article\n\nBody.\n")
P:atomic_write(canonical .. ".html", "<!--kh-meta-v2--><html><body>old render</body></html>")
local regenerated = store:render_derived(canonical, meta, false)
assert(regenerated, "old derived html must be regenerated")
local migrated = read(regenerated)
assert(migrated:find("<!--kh-meta-v2-->", 1, true), "render marker missing after migration")
assert(read(canonical .. ".html") == nil, "render_derived must remove the legacy adjacent html")

os.execute("rm -rf '" .. dir .. "'")
print("OK link card smoke: card=" .. #md .. "B migrated=" .. #migrated .. "B")
