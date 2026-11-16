local lfs = require("libs/libkoreader-lfs")
local MdToHtml = require("lib/render/md_to_html")
local ArticleStore = require("lib/article_store")
local Logger = require("lib/logger")

local Digest = {}

local function fmt_epoch(ts)
    if type(ts) ~= "number" then return nil end
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", ts)
    if ok then return s end
    return nil
end

local function date_str_from_state(state)
    if state and type(state.date_iso) == "string" and state.date_iso:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return state.date_iso
    end
    return os.date("%Y-%m-%d")
end

local function safe_text(s, fallback)
    if s == nil then return fallback or "" end
    s = tostring(s)
    if s == "" then return fallback or "" end
    return s
end

function Digest.build(state, opts)
    opts = opts or {}
    state = state or {}
    local date = opts.date or date_str_from_state(state)
    local time_str = safe_text(state.time, "Time unavailable")
    local weather = state.weather or { status = "error", line = "Weather: unavailable." }
    local hn = state.hn or { status = "error", line = "HN unavailable.", items = {} }
    local hn_items = (type(hn.items) == "table") and hn.items or {}
    local max_items = tonumber(opts.max_items) or 5
    if max_items < 1 then max_items = 1 end

    local meta = {
        id = date,
        title = "Daily Digest " .. date,
        source = "kindlehome:digest",
        date = date,
        status = "ok",
        generated_at = fmt_epoch(os.time()) or os.date("%Y-%m-%d %H:%M"),
        has_weather = weather.status ~= "disabled" and weather.line ~= nil,
        has_hn = hn.status ~= "disabled",
        weather_status = weather.status,
        hn_status = hn.status,
    }

    local md_lines = {
        "# Daily Digest — " .. date,
        "",
        "- Generated: " .. meta.generated_at,
        "- Time: " .. time_str,
        "",
        "## Weather",
        "",
        safe_text(weather.line, "Weather: unavailable."),
    }
    if weather.fetched_at then
        local ts = fmt_epoch(weather.fetched_at)
        if ts then table.insert(md_lines, "") table.insert(md_lines, "_Updated: " .. ts .. (weather.stale and " (cached)" or "") .. "_") end
    end
    if weather.status == "configure_location" then
        table.insert(md_lines, "")
        table.insert(md_lines, "Set location in Kindle Home settings (search place or enter lat/lon).")
    elseif weather.status == "error" and weather.error_kind and weather.error_kind ~= "" then
        table.insert(md_lines, "")
        table.insert(md_lines, "Weather note: " .. safe_text(weather.error_kind, "unavailable") .. ".")
    elseif weather.stale then
        table.insert(md_lines, "")
        table.insert(md_lines, "Showing cached weather.")
    end

    table.insert(md_lines, "")
    table.insert(md_lines, "## Top Hacker News")
    table.insert(md_lines, "")
    table.insert(md_lines, safe_text(hn.line, "HN unavailable."))
    if hn.fetched_at then
        local ts = fmt_epoch(hn.fetched_at)
        if ts then table.insert(md_lines, "_Updated: " .. ts .. (hn.stale and " (cached)" or "") .. "_") end
    end
    if hn.message and hn.message ~= "" and hn.message ~= hn.line then
        table.insert(md_lines, "")
        table.insert(md_lines, safe_text(hn.message))
    end
    if #hn_items == 0 then
        table.insert(md_lines, "")
        table.insert(md_lines, "No HN items available.")
    else
        table.insert(md_lines, "")
        local shown = 0
        for i, item in ipairs(hn_items) do
            if i > max_items then break end
            shown = shown + 1
            local rank = tonumber(item.rank) and tostring(item.rank) or tostring(i)
            local title = safe_text(item.title, "(untitled)")
            local bits = {}
            if tonumber(item.score) then table.insert(bits, tostring(item.score) .. " pts") end
            if tonumber(item.descendants) then table.insert(bits, tostring(item.descendants) .. " comments") end
            if item.by and item.by ~= "" then table.insert(bits, "by " .. tostring(item.by)) end
            if item.domain and item.domain ~= "" then table.insert(bits, tostring(item.domain)) end
            local suffix = ""
            if item.content_status and item.content_status ~= "ok" then
                suffix = " [status:" .. tostring(item.content_status) .. "]"
            end
            if item.url == nil then table.insert(bits, "Ask HN") end
            table.insert(md_lines, rank .. ". " .. title .. suffix)
            if #bits > 0 then
                table.insert(md_lines, "   - " .. table.concat(bits, " · "))
            end
        end
        if shown == 0 then
            table.insert(md_lines, "No HN items available.")
        end
    end

    local md = table.concat(md_lines, "\n") .. "\n"
    local body_html = MdToHtml.render(md)
    local html = MdToHtml.document({
        title = meta.title,
        meta = {
            source = meta.source,
            date = meta.date,
            status = meta.status,
            generated = meta.generated_at,
        },
        body_html = body_html,
        show_title = true,
    })

    if not (meta.has_weather or meta.has_hn) then
        meta.status = "partial"
    end
    if (#hn_items == 0 and (not weather.line or weather.status == "error")) then
        meta.status = "partial"
    end

    return {
        kind = "digest",
        id = date,
        title = meta.title,
        meta = meta,
        md = md,
        html = html,
        body_html = body_html,
        status = meta.status,
        date = date,
    }
end

function Digest.save(paths, doc)
    if not paths or type(doc) ~= "table" then return nil, "invalid_args" end
    paths:ensure_base_dirs()
    paths:ensure_dir(paths:digest_dir())
    local store = ArticleStore:new(paths)
    local meta = doc.meta or { date = doc.date or doc.id }
    meta.date = meta.date or doc.date or doc.id or os.date("%Y-%m-%d")
    local saved, err = store:save({
        kind = "digest",
        meta = meta,
        md = doc.md or "",
        body_html = doc.body_html,
    })
    if not saved then
        Logger.err("digest", "save_failed", { date = meta.date, err = tostring(err) })
        return nil, err
    end
    saved.date = meta.date
    saved.title = doc.title or meta.title
    saved.meta = meta
    saved.kind = "digest"
    Logger.info("digest", "saved", { date = meta.date, md = saved.md_path })
    return saved
end

function Digest.build_and_save(state, paths, opts)
    local doc = Digest.build(state, opts)
    local saved, err = Digest.save(paths, doc)
    if not saved then
        return nil, err, doc
    end
    for k, v in pairs(saved) do
        if doc[k] == nil then doc[k] = v end
    end
    doc.md_path = saved.md_path
    doc.html_path = saved.html_path
    doc.html = saved.html or doc.html
    return doc
end

local function is_date_file(name)
    return type(name) == "string" and name:match("^%d%d%d%d%-%d%d%-%d%d%.html$") ~= nil
end

function Digest.latest(paths)
    if not paths then return nil, "paths_unavailable" end
    local dir = paths:digest_dir()
    local ok, iter, state, var = pcall(lfs.dir, dir)
    if not ok or type(iter) ~= "function" then
        return nil, "not_found"
    end
    local latest_date = nil
    for name in iter, state, var do
        if is_date_file(name) then
            local d = name:sub(1, 10)
            if not latest_date or d > latest_date then
                latest_date = d
            end
        end
    end
    if not latest_date then
        return nil, "not_found"
    end
    return Digest.paths_for_date(paths, latest_date)
end

function Digest.paths_for_date(paths, date)
    if not paths or type(date) ~= "string" or not date:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return nil, "invalid_date"
    end
    local dir = paths:digest_dir()
    return {
        date = date,
        dir = dir,
        md = dir .. "/" .. date .. ".md",
        html = dir .. "/" .. date .. ".html",
    }
end

function Digest.load(paths, date_or_latest)
    local p, err
    if date_or_latest == nil or date_or_latest == "" or date_or_latest == "latest" then
        p, err = Digest.latest(paths)
    else
        p, err = Digest.paths_for_date(paths, date_or_latest)
    end
    if not p then return nil, err or "not_found" end

    local store = ArticleStore:new(paths)
    local html, herr = store:load_html(p.html)
    if not html then
        Logger.warn("digest", "load_failed", { date = p.date, err = tostring(herr) })
        return nil, herr or "not_found"
    end
    local md = store:load_md(p.md)
    return {
        kind = "digest",
        id = p.date,
        date = p.date,
        title = "Daily Digest " .. p.date,
        meta = { id = p.date, date = p.date, source = "kindlehome:digest", status = "ok" },
        md = md,
        html = html,
        html_path = p.html,
        md_path = p.md,
        status = "ok",
    }
end

return Digest
