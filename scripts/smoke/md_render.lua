-- Smoke test: Markdown -> HTML renderer (Lua 5.1, no KOReader deps).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return {
        info = function() end,
        warn = function(m, e) io.stderr:write("WARN ", m, " ", e, "\n") end,
        err = function(m, e) io.stderr:write("ERR ", m, " ", e, "\n") end,
    }
end

local Md = dofile(PLUGIN .. "lib/render/md_to_html.lua")

local md = table.concat({
    "# Title",
    "",
    "> by someone",
    "> HN: https://news.ycombinator.com/item?id=1",
    "",
    "#### Fourth",
    "##### Fifth",
    "###### Sixth",
    "",
    "![diagram alt](https://example.com/remote.png) and [link](https://example.com)",
    "",
    "---",
    "",
    "* one",
    "* two",
    "",
    "**bold** <script>alert(1)</script>",
    "",
    "```",
    "code <b>block</b>",
    "```",
}, "\n")

local html = Md.render(md)

assert(html:find("<h1>Title</h1>", 1, true), "h1 missing")
assert(html:find("<h4>Fourth</h4>", 1, true), "h4 missing")
assert(html:find("<h5>Fifth</h5>", 1, true), "h5 missing")
assert(html:find("<h6>Sixth</h6>", 1, true), "h6 missing")
assert(html:find("<blockquote>", 1, true), "blockquote open missing")
assert(html:find("<div>by someone</div>", 1, true), "blockquote line missing")
assert(html:find("</blockquote>", 1, true), "blockquote close missing")
assert(html:find("diagram alt", 1, true), "image alt text missing")
assert(not html:find("<img", 1, true), "remote images must not be emitted")
assert(not html:find("remote.png", 1, true), "remote image URL must be dropped")
assert(html:find('href="https://example.com"', 1, true), "safe link missing")
assert(html:find("<hr/>", 1, true), "hr missing")
assert(not html:find("<script", 1, true), "raw HTML must be escaped")
assert(html:find("&lt;script&gt;", 1, true), "escaped script missing")
assert(html:find("<code>code &lt;b&gt;block&lt;/b&gt;</code>", 1, true), "code block not escaped")

local doc = Md.document({ title = "T", body_html = html, show_title = false })
assert(doc:find("<!DOCTYPE html>", 1, true), "document must include doctype")
assert(doc:find("blockquote{", 1, true), "blockquote CSS missing")
assert(doc:find("h4{", 1, true), "h4 CSS missing")
assert(doc:find(Md.render_marker(), 1, true), "render marker missing")

local linked = Md.document({
    title = "Linked",
    meta = {
        source = "hnmd",
        hn_url = "https://news.ycombinator.com/item?id=42",
        url = "https://example.com/story",
    },
    body_html = "<p>x</p>",
})
assert(linked:find("<div>HN: <a href=", 1, true), "HN meta link missing")
assert(linked:find('href="https://news.ycombinator.com/item?id=42"', 1, true), "HN href missing")
assert(linked:find("<div>Article URL: <a href=", 1, true), "source meta link missing")
assert(linked:find('href="https://example.com/story"', 1, true), "source href missing")
assert(linked:find("<div>Source: hnmd</div>", 1, true), "Source label must stay distinct from source URL")

print("OK md render smoke: html=" .. #html .. "B doc=" .. #doc .. "B")
