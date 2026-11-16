local MdToHtml = {}

-- Relative units only: KOReader's HTML layout passes a DPI-scaled
-- `default_font_size`, while absolute CSS px would be interpreted as device
-- pixels (tiny on a 300 ppi PaperWhite 5). The same stylesheet is reused for
-- persisted .html opened in crengine, where the reader font size governs em.
local EINK_CSS = table.concat({
    "@page{margin:0;}",
    "body{font-family:serif;margin:0;padding:0.9em;color:#000;background:#fff;}",
    "h1{font-size:1.6em;line-height:1.2;margin:0 0 0.5em 0;}",
    "h2{font-size:1.3em;line-height:1.25;margin:1.1em 0 0.4em 0;}",
    "h3{font-size:1.1em;line-height:1.3;margin:0.9em 0 0.3em 0;}",
    "p{line-height:1.5;margin:0 0 0.8em 0;}",
    "ul,ol{line-height:1.5;margin:0 0 0.9em 1.2em;padding:0;}",
    "li{margin:0.2em 0;}",
    "pre{font-family:monospace;font-size:0.85em;white-space:pre-wrap;border:0.07em solid #000;padding:0.6em;margin:0.7em 0;}",
    "code{font-family:monospace;}",
    "hr{border:0;border-top:0.07em solid #000;margin:1em 0;}",
    "a{color:#000;text-decoration:underline;}",
    ".meta{font-size:0.78em;color:#222;margin:0 0 0.9em 0;}",
    ".notice{font-size:0.95em;margin:0.8em 0;padding:0.7em;border:0.07em solid #000;}",
    ".nav{margin:1.2em 0 0 0;padding-top:0.8em;border-top:0.07em solid #000;font-size:0.9em;}",
    ".navitem{margin:0.5em 0;}",
    ".footer-note{font-size:0.8em;color:#222;margin-top:1em;}",
}, "")

local function escape_html(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function sanitize_href(href)
    href = tostring(href or ""):match("^%s*(.-)%s*$") or ""
    if href == "" then return nil end
    local lower = href:lower()
    if lower:match("^https?://") or lower:match("^mailto:") then
        return href:gsub('"', "%%22")
    end
    return nil
end

local function render_inline(text)
    text = escape_html(text)
    -- code spans first, keep simple (no nesting)
    text = text:gsub("`([^`]+)`", "<code>%1</code>")
    text = text:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
    text = text:gsub("__(.-)__", "<strong>%1</strong>")
    text = text:gsub("%*(.-)%*", "<em>%1</em>")
    text = text:gsub("_(.-)_", "<em>%1</em>")
    text = text:gsub("%[(.-)%]%((.-)%)", function(label, href)
        local safe = sanitize_href(href)
        if not safe then
            return label
        end
        return '<a href="' .. safe .. '">' .. label .. "</a>"
    end)
    return text
end

local function flush_paragraph(buf, out)
    if #buf == 0 then return end
    local text = table.concat(buf, " ")
    text = text:match("^%s*(.-)%s*$") or ""
    if text ~= "" then
        table.insert(out, "<p>" .. render_inline(text) .. "</p>")
    end
    for i = #buf, 1, -1 do buf[i] = nil end
end

local function close_list(list_state, out)
    if list_state.type == "ul" then
        table.insert(out, "</ul>")
    elseif list_state.type == "ol" then
        table.insert(out, "</ol>")
    end
    list_state.type = nil
end

function MdToHtml.render(md_text)
    md_text = tostring(md_text or "")
    md_text = md_text:gsub("\r\n?", "\n")
    local lines = {}
    for line in (md_text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    local out = {}
    local pbuf = {}
    local in_code = false
    local code_lines = {}
    local list_state = { type = nil }

    local function end_block()
        flush_paragraph(pbuf, out)
        if list_state.type then close_list(list_state, out) end
    end

    for _, line in ipairs(lines) do
        if in_code then
            if line:match("^```") then
                table.insert(out, "<pre><code>" .. escape_html(table.concat(code_lines, "\n")) .. "</code></pre>")
                in_code = false
                code_lines = {}
            else
                table.insert(code_lines, line)
            end
        else
            if line:match("^```") then
                end_block()
                in_code = true
                code_lines = {}
            elseif line:match("^%s*$") then
                end_block()
            elseif line:match("^%-%-%-+$") or line:match("^%*%*%*+$") then
                end_block()
                table.insert(out, "<hr/>")
            else
                local h3 = line:match("^###%s+(.*)$")
                local h2 = h3 == nil and line:match("^##%s+(.*)$") or nil
                local h1 = (h3 == nil and h2 == nil) and line:match("^#%s+(.*)$") or nil
                local ul = line:match("^%s*[%-%*]%s+(.*)$")
                local ol = line:match("^%s*%d+%.%s+(.*)$")
                if h1 or h2 or h3 then
                    end_block()
                    if h1 then table.insert(out, "<h1>" .. render_inline(h1) .. "</h1>")
                    elseif h2 then table.insert(out, "<h2>" .. render_inline(h2) .. "</h2>")
                    else table.insert(out, "<h3>" .. render_inline(h3) .. "</h3>") end
                elseif ul then
                    flush_paragraph(pbuf, out)
                    if list_state.type ~= "ul" then
                        if list_state.type then close_list(list_state, out) end
                        table.insert(out, "<ul>")
                        list_state.type = "ul"
                    end
                    table.insert(out, "<li>" .. render_inline(ul) .. "</li>")
                elseif ol then
                    flush_paragraph(pbuf, out)
                    if list_state.type ~= "ol" then
                        if list_state.type then close_list(list_state, out) end
                        table.insert(out, "<ol>")
                        list_state.type = "ol"
                    end
                    table.insert(out, "<li>" .. render_inline(ol) .. "</li>")
                else
                    if list_state.type then close_list(list_state, out) end
                    table.insert(pbuf, (line:gsub("^%s+", ""):gsub("%s+$", "")))
                end
            end
        end
    end

    if in_code then
        table.insert(out, "<pre><code>" .. escape_html(table.concat(code_lines, "\n")) .. "</code></pre>")
    end
    end_block()

    if #out == 0 then
        table.insert(out, '<p class="notice">No content available.</p>')
    end
    return table.concat(out, "\n")
end

local function meta_html(meta)
    if type(meta) ~= "table" then return "" end
    local parts = {}
    local function add(label, value)
        if value == nil then return end
        value = tostring(value)
        if value == "" then return end
        table.insert(parts, "<div>" .. escape_html(label) .. ": " .. escape_html(value) .. "</div>")
    end
    add("Source", meta.source)
    add("Title", meta.title)
    add("Date", meta.date)
    add("ID", meta.id)
    add("Status", meta.status)
    if #parts == 0 then return "" end
    return '<div class="meta">' .. table.concat(parts, "") .. "</div>"
end

-- Body fragment only (no <html>/<head>/<style>): this is what
-- ScrollHtmlWidget/HtmlBoxWidget expect, since they wrap it themselves.
function MdToHtml.document_body(opts)
    opts = opts or {}
    local title = escape_html(opts.title or (opts.meta and opts.meta.title) or "Kindle Home")
    local body_html = opts.body_html
    if not body_html then
        body_html = MdToHtml.render(opts.md or "")
    end
    local header = ""
    if opts.show_title ~= false then
        header = "<h1>" .. title .. "</h1>"
    end
    return table.concat({
        header,
        meta_html(opts.meta),
        body_html,
    })
end

-- Full standalone document, used for persisted .html files.
function MdToHtml.document(opts)
    opts = opts or {}
    return table.concat({
        "<html><head><meta charset='utf-8'/>",
        "<style>", EINK_CSS, (opts.css or ""), "</style>",
        "</head><body>",
        MdToHtml.document_body(opts),
        "</body></html>",
    })
end

function MdToHtml.css()
    return EINK_CSS
end

function MdToHtml.escape(s)
    return escape_html(s)
end

function MdToHtml.notice_html(message)
    return '<div class="notice">' .. escape_html(message or "Notice") .. "</div>"
end

return MdToHtml
