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

function Todos.due_bounds(now, due_days)
    now = tonumber(now) or os.time()
    due_days = tonumber(due_days) or DEFAULT_DUE_DAYS
    if due_days < 1 then due_days = 1 end
    if due_days > 30 then due_days = 30 end
    return os.date("!%Y-%m-%d", now), os.date("!%Y-%m-%d", now + due_days * 86400)
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

-- Apply a local write to a cached todos payload. The server response is the
-- authoritative task for create/update; delete needs only the id.
function Todos.merge_payload(payload, action, task, id, opts)
    opts = opts or {}
    local today, limit = Todos.due_bounds(opts.now, opts.due_days)
    payload = payload or {}
    local items = {}
    for _, raw in ipairs(payload.items or {}) do
        local normalized = normalize_task(raw)
        if normalized then table.insert(items, normalized) end
    end
    local changed = normalize_task(task)
    if action == "create" then
        if changed then table.insert(items, changed) end
    elseif action == "update" then
        if changed then
            local found = false
            for index, existing in ipairs(items) do
                if existing.id == changed.id then
                    items[index] = changed
                    found = true
                    break
                end
            end
            if not found then table.insert(items, changed) end
        end
    elseif action == "delete" then
        local keep = {}
        for _, existing in ipairs(items) do
            if existing.id ~= tostring(id) then table.insert(keep, existing) end
        end
        items = keep
    end
    table.sort(items, sort_tasks)

    local counts = { open = 0, done = 0, total = #items, due_soon = 0, overdue = 0 }
    local by_tag = {}
    for _, item in ipairs(items) do
        local class = item.done and nil or Todos.classify_due(item.due_date, today, limit)
        if item.done then counts.done = counts.done + 1 else counts.open = counts.open + 1 end
        if class == "due_soon" then counts.due_soon = counts.due_soon + 1
        elseif class == "overdue" then counts.overdue = counts.overdue + 1 end
        for _, tag in ipairs(item.tags or {}) do
            local entry = by_tag[tag]
            if not entry then
                entry = { tag = tag, open = 0, done = 0, total = 0, due_soon = 0, overdue = 0 }
                by_tag[tag] = entry
            end
            if item.done then entry.done = entry.done + 1 else entry.open = entry.open + 1 end
            if class == "due_soon" then entry.due_soon = entry.due_soon + 1
            elseif class == "overdue" then entry.overdue = entry.overdue + 1 end
            entry.total = entry.total + 1
        end
    end
    local names = {}
    for name in pairs(by_tag) do table.insert(names, name) end
    table.sort(names)
    local tags = {}
    for _, name in ipairs(names) do table.insert(tags, by_tag[name]) end

    return {
        schema_version = payload.schema_version or Todos.API_VERSION,
        generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        filter = payload.filter or { status = "all" },
        counts = counts,
        tags = tags,
        returned_count = #items,
        truncated = payload.truncated and true or false,
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
    }
end

-- The HTTP layer returns 400 bodies as text. Surface the server's field name
-- as an error_kind so ui/messages.lua can show an actionable notice.
local function tag_write_error(res)
    if res.ok or res.status ~= 400 or type(res.body) ~= "string" then return res end
    if res.body:find('"due_date"', 1, true) then
        res.error_kind = "invalid_due_date"
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
    local url = base .. "/todos?status=" .. urlencode(status)
    local tag = to_str(opts.tag)
    if tag and tag ~= "" then url = url .. "&tag=" .. urlencode(tag) end
    local due_days = tonumber(opts.due_days)
    if due_days then url = url .. "&due_days=" .. tostring(due_days) end

    local res = Http.get_json(url, request_opts(config, opts))
    if not res.ok then
        Logger.warn("todos", "index_failed", { kind = res.error_kind, status = res.status })
        return res
    end

    local data = res.json
    if type(data) ~= "table" then
        return { ok = false, error_kind = "parse", error = "invalid_response" }
    end
    if to_num(data.schema_version) ~= Todos.API_VERSION then
        return { ok = false, error_kind = "parse", error = "unsupported_schema" }
    end
    if type(data.items) ~= "table" or type(data.counts) ~= "table" then
        return { ok = false, error_kind = "parse", error = "missing_fields" }
    end

    local items = {}
    for _, raw in ipairs(data.items) do
        local task = normalize_task(raw)
        if task then table.insert(items, task) end
    end
    local filter = type(data.filter) == "table" and data.filter or {}
    local payload = {
        schema_version = Todos.API_VERSION,
        generated_at = to_str(data.generated_at),
        filter = { tag = to_str(filter.tag), status = to_str(filter.status) or status },
        counts = normalize_counts(data.counts),
        tags = normalize_tag_counts(data.tags),
        returned_count = to_num(data.returned_count),
        truncated = data.truncated and true or false,
        items = items,
        source_base_url = base,
    }
    Logger.info("todos", "index_ok", { count = #items, status = res.status })
    return { ok = true, status = res.status, payload = payload, fetched_at = os.time() }
end

function Todos.create(config, text, tags, details, due_date, opts)
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    if type(text) ~= "string" or text == "" then
        return { ok = false, error_kind = "parse", error = "invalid_text" }
    end
    local payload = { text = text }
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
        tag_write_error(res)
        Logger.warn("todos", "create_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    local task = normalize_task(res.json)
    if not task then
        return { ok = false, error_kind = "parse", error = "invalid_task", status = res.status }
    end
    Logger.info("todos", "create_ok", { id = task.id })
    return { ok = true, status = res.status, task = task }
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

    local res = Http.request_json(base .. "/todos/tasks/" .. urlencode(id), write_opts(config, opts, "PATCH", body))
    if not res.ok then
        tag_write_error(res)
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
    local res = Http.request(base .. "/todos/tasks/" .. urlencode(id), write_opts(config, opts, "DELETE", nil))
    if not res.ok then
        Logger.warn("todos", "delete_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    Logger.info("todos", "delete_ok", { id = id })
    return { ok = true, status = res.status }
end

return Todos
