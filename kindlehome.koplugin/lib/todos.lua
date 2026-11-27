-- SPDX-License-Identifier: MIT
local Http = require("lib/http")
local Hnmd = require("lib/hnmd")
local Logger = require("lib/logger")

local Todos = {}

Todos.API_VERSION = 1

local ID_PATTERN = "^[A-Za-z0-9_%-]+$"
local TAG_PATTERN = "^[a-z0-9][a-z0-9_%-]*$"
local DUE_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"
local DEFAULT_DUE_DAYS = 3
local DEFAULT_PAGE_LIMIT = 500
local MAX_PAGES = 3

-- hnmd 1.5.0 accepts a strong ETag ("N") or a weak one in If-Match. We store
-- `revision` in the normalized task, so a strong validator is always available.
local function if_match_for(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.if_match ~= nil and opts.if_match ~= "" then
        return tostring(opts.if_match)
    end
    local revision = tonumber(opts.revision)
    if revision then
        return string.format('"%d"', math.floor(revision))
    end
    return nil
end

-- Deterministic, URL-safe id for idempotent creation (hnmd 1.5.0). The format
-- stays inside the server's ^[A-Za-z0-9_-]{1,64}$ pattern.
local function new_task_id()
    local t = tonumber(os.time()) or 0
    local r = math.random(0, 2147483647)
    local function pair(n)
        return string.format("%04x%04x", math.floor(n / 65536) % 65536, n % 65536)
    end
    return pair(t) .. pair(r)
end

math.randomseed((tonumber(os.time()) or 1) + math.floor((os.clock() or 0) * 1000))

function Todos.new_task_id()
    return new_task_id()
end

local function to_str(v)
    if v == nil then return nil end
    return tostring(v)
end

local function to_num(v)
    local n = tonumber(v)
    if type(n) ~= "number" then return 0 end
    return n
end

local function valid_id(id)
    return type(id) == "string" and id ~= "" and #id <= 64 and id:match(ID_PATTERN) ~= nil
end

local function valid_tag(tag)
    return type(tag) == "string" and #tag >= 1 and #tag <= 32 and tag:match(TAG_PATTERN) ~= nil
end

-- Deadlines are canonical YYYY-MM-DD strings. os.time/os.date are used only to
-- reject impossible calendar dates; both are available in Lua 5.1/LuaJIT.
local function normalize_due_date(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" then return nil end
    local year, month, day = text:match(DUE_PATTERN)
    if not year then return nil, "invalid_due_date" end
    local y, m, d = tonumber(year), tonumber(month), tonumber(day)
    if not y or not m or not d or m < 1 or m > 12 or d < 1 or d > 31 then
        return nil, "invalid_due_date"
    end
    local ok, stamp = pcall(os.time, { year = y, month = m, day = d, hour = 12, min = 0, sec = 0 })
    if not ok or not stamp then return nil, "invalid_due_date" end
    local ok_date, parts = pcall(os.date, "!*t", stamp)
    if not ok_date or type(parts) ~= "table" then return nil, "invalid_due_date" end
    if parts.year ~= y or parts.month ~= m or parts.day ~= d then
        return nil, "invalid_due_date"
    end
    return text
end

function Todos.valid_due_date(value)
    if value == nil or value == "" then return true end
    local _, err = normalize_due_date(value)
    return err == nil
end

-- With a configured IANA timezone the device's local day matches the server's
-- `tz` interpretation; without one both sides use UTC (TODO_TIMEZONE default).
function Todos.due_bounds(now, due_days, use_local)
    now = tonumber(now) or os.time()
    due_days = tonumber(due_days) or DEFAULT_DUE_DAYS
    if due_days < 1 then due_days = 1 end
    if due_days > 30 then due_days = 30 end
    local fmt = use_local and "%Y-%m-%d" or "!%Y-%m-%d"
    return os.date(fmt, now), os.date(fmt, now + due_days * 86400)
end

function Todos.classify_due(due, today, limit)
    if type(due) ~= "string" or due == "" then return nil end
    if due < today then return "overdue" end
    if due <= limit then return "due_soon" end
    return nil
end

function Todos.format_due(due)
    if type(due) ~= "string" then return nil end
    local y, m, d = due:match(DUE_PATTERN)
    if not y then return due end
    return d .. "-" .. m .. "-" .. y
end

local function urlencode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_~%.])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function normalized_tags(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, value in ipairs(raw) do
        local tag = to_str(value)
        if valid_tag(tag) then
            local seen = false
            for _, existing in ipairs(out) do
                if existing == tag then seen = true break end
            end
            if not seen and #out < 10 then table.insert(out, tag) end
        end
    end
    return out
end

local function normalize_task(raw)
    if type(raw) ~= "table" then return nil end
    local id = to_str(raw.id)
    if not valid_id(id) then return nil end
    local title = to_str(raw.title)
    if not title or title == "" then return nil end
    return {
        id = id,
        title = title,
        tags = normalized_tags(raw.tags),
        details = to_str(raw.details) or "",
        due_date = normalize_due_date(raw.due_date),
        done = raw.done and true or false,
        created_at = to_str(raw.created_at),
        updated_at = to_str(raw.updated_at),
        done_at = to_str(raw.done_at),
        revision = to_num(raw.revision),
    }
end

local function normalize_counts(raw)
    raw = type(raw) == "table" and raw or {}
    return {
        open = to_num(raw.open),
        done = to_num(raw.done),
        total = to_num(raw.total),
        due_soon = to_num(raw.due_soon),
        overdue = to_num(raw.overdue),
    }
end

local function normalize_tag_counts(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for _, entry in ipairs(raw) do
        if type(entry) == "table" then
            local tag = to_str(entry.tag)
            if valid_tag(tag) then
                table.insert(out, {
                    tag = tag,
                    open = to_num(entry.open),
                    done = to_num(entry.done),
                    total = to_num(entry.total),
                    due_soon = to_num(entry.due_soon),
                    overdue = to_num(entry.overdue),
                })
            end
        end
    end
    return out
end

-- Parse the free-form Tags field. Values may be separated by spaces or commas
-- and may carry a leading '#'. An empty field is valid and means "no tags".
function Todos.parse_tags(input)
    local out = {}
    if input == nil then return out, nil end
    for part in tostring(input):gmatch("[^%s,]+") do
        local tag = part:match("^#+(.+)$") or part
        tag = tag:lower()
        if not valid_tag(tag) then return nil, "invalid_tags" end
        local seen = false
        for _, existing in ipairs(out) do
            if existing == tag then seen = true break end
        end
        if not seen then
            if #out >= 10 then return nil, "invalid_tags" end
            table.insert(out, tag)
        end
    end
    return out, nil
end

local function primary_tag(task)
    return (task.tags and task.tags[1]) or ""
end

local function sort_tasks(a, b)
    if a.done ~= b.done then return not a.done end
    if not a.done then
        local da, db = a.due_date, b.due_date
        if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
        if da and db and da ~= db then return da < db end
        local ta, tb = primary_tag(a), primary_tag(b)
        if ta == "" and tb ~= "" then return false end
        if ta ~= "" and tb == "" then return true end
        if ta ~= tb then return ta < tb end
        local ca, cb = a.created_at or "", b.created_at or ""
        if ca ~= cb then return ca < cb end
        return tostring(a.id) < tostring(b.id)
    end
    local da, db = a.done_at, b.done_at
    if (da == nil) ~= (db == nil) then return da ~= nil end
    if da and db and da ~= db then return da > db end
    return tostring(a.id) < tostring(b.id)
end

local function clamp_count(value)
    local n = math.floor(tonumber(value) or 0)
    if n < 0 then return 0 end
    return n
end

local function tag_counts_from_payload(payload)
    local out = {}
    for _, entry in ipairs(normalize_tag_counts(payload and payload.tags)) do
        out[entry.tag] = entry
    end
    return out
end

local function adjust_tag(counts, tag, d_open, d_done)
    local entry = counts[tag]
    if not entry then
        entry = { tag = tag, open = 0, done = 0, total = 0, due_soon = 0, overdue = 0 }
        counts[tag] = entry
    end
    entry.open = clamp_count(entry.open + d_open)
    entry.done = clamp_count(entry.done + d_done)
    entry.total = clamp_count(entry.total + d_open + d_done)
end

local function serialized_tag_counts(counts)
    local names = {}
    for name, entry in pairs(counts) do
        if entry.total > 0 then table.insert(names, name) end
    end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do table.insert(out, counts[name]) end
    return out
end

local function task_tag_counts(task)
    if task.done then return 0, 1 end
    return 1, 0
end

local function tag_delta(counts, old_task, new_task, d_open, d_done)
    local old_tags, new_tags = {}, {}
    for _, tag in ipairs(old_task.tags or {}) do old_tags[tag] = true end
    for _, tag in ipairs(new_task.tags or {}) do new_tags[tag] = true end
    for tag in pairs(old_tags) do
        local add_open, add_done
        if new_tags[tag] then
            -- Same tag, possibly flipped done: inherit the task's delta.
            add_open, add_done = d_open, d_done
        else
            local open, done = task_tag_counts(old_task)
            add_open, add_done = -open, -done
        end
        adjust_tag(counts, tag, add_open, add_done)
    end
    for tag in pairs(new_tags) do
        if not old_tags[tag] then
            local open, done = task_tag_counts(new_task)
            adjust_tag(counts, tag, open, done)
        end
    end
end

-- Apply a local write to a cached todos payload. The server response is the
-- authoritative task for create/update; delete needs only the id.
--
-- Global counters come from the server and stay authoritative. Only the
-- deterministic deltas (open/done/total and per-tag open/done/total) are
-- applied locally. `due_soon`/`overdue` are never recomputed from the cached
-- item window: that window may be partial and the device's day can differ
-- from the server's `tz`, which produced false overdue counts. The caller
-- refreshes from the server right after a successful write.
function Todos.merge_payload(payload, action, task, id)
    payload = payload or {}
    local partial = payload.partial and true or false
    local items, by_id = {}, {}
    for _, raw in ipairs(payload.items or {}) do
        local normalized = normalize_task(raw)
        if normalized then
            table.insert(items, normalized)
            by_id[normalized.id] = normalized
        end
    end

    local counts = normalize_counts(payload.counts)
    local tag_counts = tag_counts_from_payload(payload)
    local changed = normalize_task(task)
    local d_open, d_done = 0, 0

    if action == "create" and changed then
        local existing = by_id[changed.id]
        if existing then
            -- Idempotent retry: replace the stored task, never double count it.
            for index, item in ipairs(items) do
                if item.id == changed.id then items[index] = changed break end
            end
            if existing.done ~= changed.done then
                if changed.done then d_open, d_done = -1, 1 else d_open, d_done = 1, -1 end
            end
            tag_delta(tag_counts, existing, changed, d_open, d_done)
        else
            table.insert(items, changed)
            if changed.done then d_done = 1 else d_open = 1 end
            for _, tag in ipairs(changed.tags or {}) do
                adjust_tag(tag_counts, tag, changed.done and 0 or 1, changed.done and 1 or 0)
            end
        end
    elseif action == "update" and changed then
        local existing = by_id[changed.id]
        if existing then
            for index, item in ipairs(items) do
                if item.id == changed.id then items[index] = changed break end
            end
            if existing.done ~= changed.done then
                if changed.done then d_open, d_done = -1, 1 else d_open, d_done = 1, -1 end
            end
            tag_delta(tag_counts, existing, changed, d_open, d_done)
        else
            -- Outside the cached window: no counter delta can be known locally.
            table.insert(items, changed)
        end
    elseif action == "delete" then
        local target = tostring(id)
        for index, item in ipairs(items) do
            if item.id == target then
                if item.done then d_done = -1 else d_open = -1 end
                for _, tag in ipairs(item.tags or {}) do
                    adjust_tag(tag_counts, tag, item.done and 0 or -1, item.done and -1 or 0)
                end
                table.remove(items, index)
                break
            end
        end
    end

    table.sort(items, sort_tasks)
    counts.open = clamp_count(counts.open + d_open)
    counts.done = clamp_count(counts.done + d_done)
    counts.total = clamp_count(counts.total + d_open + d_done)
    -- counts.due_soon and counts.overdue keep the server's values on purpose.

    return {
        schema_version = payload.schema_version or Todos.API_VERSION,
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        filter = payload.filter or { status = "all" },
        counts = counts,
        tags = serialized_tag_counts(tag_counts),
        offset = payload.offset,
        limit = payload.limit,
        has_more = payload.has_more and true or false,
        next_offset = payload.next_offset,
        returned_count = #items,
        truncated = payload.truncated and true or false,
        partial = partial,
        items = items,
        source_base_url = payload.source_base_url,
    }
end

local function request_opts(config, opts)
    opts = opts or {}
    local api_key = config and config:get("hnmd_api_key") or ""
    return {
        timeout_s = opts.timeout_s or (config and config:get("http_timeout_s")) or 10,
        max_bytes = opts.max_bytes or (config and config:get("http_max_bytes")) or 262144,
        retries = 1,
        bearer_token = (type(api_key) == "string" and api_key ~= "") and api_key or nil,
        accept = "application/json",
        if_match = opts.if_match,
        if_none_match = opts.if_none_match,
    }
end

-- hnmd 1.5.0 returns one JSON error shape. Map `field` to the existing
-- validation error kinds so ui/messages.lua can show an actionable notice.
local FIELD_ERRORS = {
    text = "invalid_text",
    tags = "invalid_tags",
    details = "invalid_details",
    due_date = "invalid_due_date",
    tz = "invalid_timezone",
    due_days = "invalid_due_days",
    limit = "invalid_limit",
    offset = "invalid_offset",
    id = "invalid_task_id",
}

local function classify_write_error(res)
    if res.ok then return res end
    local code = res.error_code or ""
    if code == "precondition_required" or code == "revision_conflict"
            or code == "forbidden" then
        res.error_kind = code
    elseif res.status == 403 then
        res.error_kind = "forbidden"
    elseif code == "invalid_request" or res.status == 400 then
        res.error_kind = FIELD_ERRORS[res.error_field]
            or (res.error_field and "invalid_field")
            or "invalid_text"
    end
    return res
end

local function write_opts(config, opts, method, payload)
    local merged = request_opts(config, opts)
    merged.method = method
    if method == "POST" then
        merged.json_body = payload
        merged.retries = 0
    elseif method == "PATCH" then
        merged.json_body = payload
    else
        merged.body = ""
    end
    if method == "POST" or method == "PATCH" then
        -- rapidjson encodes an empty Lua table as {} by default; the API needs [].
        merged.json_options = { empty_table_as_array = true }
    end
    return merged
end

function Todos.fetch_index(config, opts)
    opts = opts or {}
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    local status = "all"
    if opts.status == "open" or opts.status == "done" or opts.status == "all"
            or opts.status == "due_soon" or opts.status == "overdue" then
        status = opts.status
    end
    local tag = to_str(opts.tag)
    local due_days = tonumber(opts.due_days)
    local tz = to_str(config and config:get("todos_timezone")) or ""
    -- Lua 5.1 patterns cannot repeat a capture, so validate the segments with
    -- a flat character class plus structural checks instead.
    if #tz > 64 or not tz:match("^[%w%+%-_/]+$")
            or tz:sub(1, 1) == "/" or tz:sub(-1) == "/" or tz:find("//", 1, true) then
        tz = ""
    end

    -- hnmd 1.5.0 paginates /todos. Follow next_offset so the UI list matches
    -- the server's global counters, with a hard page cap for e-ink memory and
    -- the shared refresh budget.
    local max_pages = tonumber(opts.max_pages) or MAX_PAGES
    if max_pages < 1 then max_pages = 1 end
    if max_pages > 10 then max_pages = 10 end
    local items, seen, first = {}, {}, nil
    local offset, pages = 0, 0
    local has_more, next_offset, byte_trimmed, partial = false, nil, false, false

    while true do
        local url = base .. "/todos?status=" .. urlencode(status)
            .. "&limit=" .. tostring(DEFAULT_PAGE_LIMIT)
            .. "&offset=" .. tostring(offset)
        if tag and tag ~= "" then url = url .. "&tag=" .. urlencode(tag) end
        if due_days then url = url .. "&due_days=" .. tostring(due_days) end
        if tz ~= "" then url = url .. "&tz=" .. urlencode(tz) end

        local res = Http.get_json(url, request_opts(config, opts))
        if not res.ok then
            if pages == 0 then
                Logger.warn("todos", "index_failed", { kind = res.error_kind, status = res.status })
                return res
            end
            Logger.warn("todos", "page_failed", { kind = res.error_kind, page = pages })
            partial = true
            break
        end

        local data = res.json
        if type(data) ~= "table" then
            return { ok = false, error_kind = "parse", error = "invalid_response" }
        end
        if pages == 0 then
            first = data
            if to_num(data.schema_version) ~= Todos.API_VERSION then
                return { ok = false, error_kind = "parse", error = "unsupported_schema" }
            end
            if type(data.items) ~= "table" or type(data.counts) ~= "table" then
                return { ok = false, error_kind = "parse", error = "missing_fields" }
            end
        elseif type(data.items) ~= "table" then
            partial = true
            break
        end

        for _, raw in ipairs(data.items) do
            local task = normalize_task(raw)
            if task and not seen[task.id] then
                seen[task.id] = true
                table.insert(items, task)
            end
        end

        has_more = data.has_more and true or false
        next_offset = tonumber(data.next_offset)
        byte_trimmed = byte_trimmed or (data.truncated and true or false)
        pages = pages + 1

        if not has_more then break end
        if not next_offset or next_offset <= offset then
            partial = true
            break
        end
        if pages >= max_pages then
            partial = true
            break
        end
        offset = next_offset
    end

    local data = first
    local filter = type(data.filter) == "table" and data.filter or {}
    local payload = {
        schema_version = Todos.API_VERSION,
        generated_at = to_str(data.generated_at),
        filter = { tag = to_str(filter.tag), status = to_str(filter.status) or status,
                   due_days = tonumber(filter.due_days) },
        counts = normalize_counts(data.counts),
        tags = normalize_tag_counts(data.tags),
        offset = tonumber(data.offset) or 0,
        limit = tonumber(data.limit) or DEFAULT_PAGE_LIMIT,
        has_more = has_more,
        next_offset = next_offset,
        returned_count = #items,
        truncated = byte_trimmed,
        partial = partial,
        items = items,
        source_base_url = base,
    }
    Logger.info("todos", "index_ok", { count = #items, pages = pages, partial = partial })
    return { ok = true, payload = payload, fetched_at = os.time() }
end

function Todos.create(config, text, tags, details, due_date, opts)
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    if type(text) ~= "string" or text == "" then
        return { ok = false, error_kind = "parse", error = "invalid_text" }
    end
    -- hnmd 1.5.0 accepts a client-generated id: a manual retry after a lost
    -- response returns 200 with the stored task instead of creating a duplicate.
    local payload = { id = new_task_id(), text = text }
    if type(tags) == "table" and #tags > 0 then payload.tags = tags end
    if details ~= nil then
        if type(details) ~= "string" or #details > 1000 then
            return { ok = false, error_kind = "parse", error = "invalid_details" }
        end
        if details ~= "" then payload.details = details end
    end
    if due_date ~= nil then
        local due, err = normalize_due_date(due_date)
        if err then
            return { ok = false, error_kind = err, error = err }
        end
        if due then payload.due_date = due end
    end
    local res = Http.request_json(base .. "/todos/tasks", write_opts(config, opts, "POST", payload))
    if not res.ok then
        classify_write_error(res)
        Logger.warn("todos", "create_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    local task = normalize_task(res.json)
    if not task then
        return { ok = false, error_kind = "parse", error = "invalid_task", status = res.status }
    end
    Logger.info("todos", "create_ok", { id = task.id, status = res.status })
    return { ok = true, status = res.status, task = task, existed = res.status == 200 }
end

function Todos.update(config, id, patch, opts)
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    if not valid_id(id) then
        return { ok = false, error_kind = "parse", error = "invalid_id" }
    end
    if type(patch) ~= "table" then
        return { ok = false, error_kind = "parse", error = "invalid_patch" }
    end
    local body = {}
    if patch.text ~= nil then
        if type(patch.text) ~= "string" or patch.text == "" then
            return { ok = false, error_kind = "parse", error = "invalid_text" }
        end
        body.text = patch.text
    end
    if patch.tags ~= nil then
        if type(patch.tags) ~= "table" then
            return { ok = false, error_kind = "parse", error = "invalid_tags" }
        end
        local tags, tag_err = Todos.parse_tags(table.concat(patch.tags, " "))
        if tag_err then
            return { ok = false, error_kind = "invalid_tags", error = tag_err }
        end
        body.tags = tags
    end
    if patch.details ~= nil then
        if type(patch.details) ~= "string" or #patch.details > 1000 then
            return { ok = false, error_kind = "parse", error = "invalid_details" }
        end
        body.details = patch.details
    end
    if patch.due_date ~= nil then
        local due, err = normalize_due_date(patch.due_date)
        if err then
            return { ok = false, error_kind = err, error = err }
        end
        body.due_date = due or ""
    end
    if patch.done ~= nil then body.done = patch.done and true or false end
    if next(body) == nil then
        return { ok = false, error_kind = "parse", error = "empty_patch" }
    end

    local if_match = if_match_for(opts)
    if not if_match then
        -- hnmd 1.5.0 rejects writes without If-Match with 428; fail locally so
        -- the UI can refresh and retry with a known revision.
        return { ok = false, error_kind = "missing_revision", error = "missing_revision" }
    end
    local write_opts_for_patch = write_opts(config, opts, "PATCH", body)
    write_opts_for_patch.if_match = if_match
    local res = Http.request_json(base .. "/todos/tasks/" .. urlencode(id), write_opts_for_patch)
    if not res.ok then
        classify_write_error(res)
        Logger.warn("todos", "update_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    local task = normalize_task(res.json)
    if not task then
        return { ok = false, error_kind = "parse", error = "invalid_task", status = res.status }
    end
    Logger.info("todos", "update_ok", { id = task.id })
    return { ok = true, status = res.status, task = task }
end

function Todos.delete_task(config, id, opts)
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    if not valid_id(id) then
        return { ok = false, error_kind = "parse", error = "invalid_id" }
    end
    local if_match = if_match_for(opts)
    if not if_match then
        return { ok = false, error_kind = "missing_revision", error = "missing_revision" }
    end
    local write_opts_for_delete = write_opts(config, opts, "DELETE", nil)
    write_opts_for_delete.if_match = if_match
    local res = Http.request(base .. "/todos/tasks/" .. urlencode(id), write_opts_for_delete)
    if not res.ok then
        classify_write_error(res)
        Logger.warn("todos", "delete_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    Logger.info("todos", "delete_ok", { id = id })
    return { ok = true, status = res.status }
end

return Todos
