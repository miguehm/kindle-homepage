-- SPDX-License-Identifier: MIT
-- Smoke test: ArticleStore:ensure_local download/promote/fallback logic with
-- the network client stubbed. Uses a real temp directory for the files.
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

local downloads = 0
local fake_md = "# Fake title\n\n> by tester\n> HN: https://news.ycombinator.com/item?id=9\n\n![chart](https://example.com/chart.png)\n\n#### Section\n\nBody.\n"
local fail_next = nil
local fail_should_write_partial = false

package.preload["lib/hnmd"] = function()
    return {
        download_article = function(_, item, tmp_path)
            downloads = downloads + 1
            if fail_next then
                if fail_should_write_partial then
                    local pf = assert(io.open(tmp_path, "wb"))
                    pf:write("partial")
                    pf:close()
                end
                return { ok = false, error_kind = fail_next, error = "stubbed" }
            end
            local f = assert(io.open(tmp_path, "wb"))
            f:write(fake_md)
            f:close()
            return { ok = true, status = 200, bytes = #fake_md }
        end,
    }
end

local Store = dofile(PLUGIN .. "lib/article_store.lua")

local dir = os.tmpname()
os.remove(dir)
assert(os.execute("mkdir -p '" .. dir .. "'") == 0 or true)

local P = {}
function P:articles_hn_dir() return dir end
function P:cache_dir() return dir .. "/cache" end
function P:ephemeral_articles_dir() return self:cache_dir() .. "/articles" end
function P:article_html_path(p)
    return self:ephemeral_articles_dir() .. "/" .. tostring(p:match("([^/]+)$")) .. ".html"
end
function P:article_md_path(item)
    local slug = tostring(item.title or "article"):lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    return dir .. "/" .. tostring(item.id) .. "-" .. slug .. ".md"
end
function P:atomic_write(path, content)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then os.execute("mkdir -p '" .. parent .. "'") end
    local tmp = path .. ".atomic"
    local f = assert(io.open(tmp, "wb"))
    f:write(content)
    f:close()
    assert(os.rename(tmp, path))
    return true
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return #data, data
end

local store = Store:new(P)
local item = { id = "123", title = "Fake title", content_status = "ok", content_url = "/v1/articles/123.md" }
local md_path = "/" .. dir:gsub("^/+", "") .. "/123-fake-title.md"

local res = store:ensure_local(nil, item)
assert(res.ok, "first download should succeed")
assert(downloads == 1, "download should run once")
local size, md = file_size(res.md_path or md_path)
assert(size and size > 0, ".md should be written")
assert(md:sub(1, 12) == "# Fake title", ".md should hold raw markdown without frontmatter")
local hsize, html = file_size(res.html_path)
assert(hsize and hsize > 0, "ephemeral html should be written")
assert(html:find("<blockquote>", 1, true), "derived html should render blockquote")
assert(html:find("<h4>Section</h4>", 1, true), "derived html should render h4")
assert(html:find('<a href="https://example.com/chart.png">chart</a>', 1, true),
    "derived html should render image markdown as an alt-text link")
assert(res.html_path:sub(1, #P:ephemeral_articles_dir() + 1) == P:ephemeral_articles_dir() .. "/",
    "derived html must live under the cache, not the content folder")
assert(file_size(md_path .. ".html") == nil, "no .html may be written next to the canonical .md")

local legacy = md_path .. ".html"
local legacy_f = assert(io.open(legacy, "wb"))
legacy_f:write("<!--kh-meta-v2--><html><body>legacy</body></html>")
legacy_f:close()
local regenerated = assert(store:render_derived(md_path, item, true))
assert(regenerated == res.html_path, "render_derived must use the ephemeral path")
assert(file_size(legacy) == nil, "render_derived must remove the legacy adjacent .html")

local again = store:ensure_local(nil, item)
assert(again.ok, "second call should succeed")
assert(downloads == 1, "local copy must be reused without re-download")

fail_next = "http_404"
local forced = store:ensure_local(nil, item, { force = true })
assert(not forced.ok and forced.error_kind == "http_404", "404 must surface")
assert(forced.stale == true, "existing local copy must be reported as stale")
assert(forced.md_path == md_path, "stale md path should be returned")
local kept = file_size(md_path)
assert(kept and kept > 0, "404 must not delete the local copy")

local item2 = { id = "456", title = "Missing", content_status = "ok", content_url = "/v1/articles/456.md" }
local item2_path = "/" .. dir:gsub("^/+", "") .. "/456-missing.md"
fail_next = "too_large"
fail_should_write_partial = true
local failed = store:ensure_local(nil, item2)
assert(not failed.ok and failed.error_kind == "too_large", "too_large must surface")
assert(file_size(item2_path) == nil, "failed download must not leave the .md")
local tmp_left = file_size(item2_path .. ".tmp")
assert(tmp_left == nil, "failed download must remove the .tmp file")

fail_next = nil
fail_should_write_partial = false
local narr = { id = "789", title = "No content", content_status = "no_content" }
local before = downloads
local no = store:ensure_local(nil, narr)
assert(not no.ok and no.error_kind == "no_content", "no_content must be reported")
assert(downloads == before, "no_content must not trigger a download")

os.execute("rm -rf '" .. dir .. "'")
print("OK article download smoke: downloads=" .. downloads)
