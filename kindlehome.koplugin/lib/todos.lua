-- SPDX-License-Identifier: MIT
local Http = require("lib/http")
local Hnmd = require("lib/hnmd")
local Logger = require("lib/logger")

local Todos = {}

Todos.API_VERSION = 1

local ID_PATTERN = "^[A-Za-z0-9_%-]+$"
local TAG_PATTERN = "^[a-z0-9][a-z0-9_%-]*$"

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
                })
            end
        end
    end
    return out
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
    return merged
end

function Todos.fetch_index(config, opts)
    opts = opts or {}
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    local status = "all"
    if opts.status == "open" or opts.status == "done" or opts.status == "all" then
        status = opts.status
    end
    local url = base .. "/todos?status=" .. urlencode(status)
    local tag = to_str(opts.tag)
    if tag and tag ~= "" then url = url .. "&tag=" .. urlencode(tag) end

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

function Todos.fetch_tags(config, opts)
    opts = opts or {}
    local base = Hnmd.base_url(config)
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    local res = Http.get_json(base .. "/todos/tags", request_opts(config, opts))
    if not res.ok then
        Logger.warn("todos", "tags_failed", { kind = res.error_kind, status = res.status })
        return res
    end
    local data = res.json
    if type(data) ~= "table" or to_num(data.schema_version) ~= Todos.API_VERSION then
        return { ok = false, error_kind = "parse", error = "invalid_response" }
    end
    return {
        ok = true,
        status = res.status,
        payload = {
            counts = normalize_counts(data.counts),
            tags = normalize_tag_counts(data.tags),
            untagged = normalize_counts(data.untagged),
            generated_at = to_str(data.generated_at),
        },
        fetched_at = os.time(),
    }
end

function Todos.create(config, text, tags, details, opts)
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
    local res = Http.request_json(base .. "/todos/tasks", write_opts(config, opts, "POST", payload))
    if not res.ok then
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
        body.tags = patch.tags
    end
    if patch.details ~= nil then
        if type(patch.details) ~= "string" or #patch.details > 1000 then
            return { ok = false, error_kind = "parse", error = "invalid_details" }
        end
        body.details = patch.details
    end
    if patch.done ~= nil then body.done = patch.done and true or false end
    if next(body) == nil then
        return { ok = false, error_kind = "parse", error = "empty_patch" }
    end

    local res = Http.request_json(base .. "/todos/tasks/" .. urlencode(id), write_opts(config, opts, "PATCH", body))
    if not res.ok then
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
