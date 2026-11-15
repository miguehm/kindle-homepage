local Http = require("lib/http")
local Logger = require("lib/logger")

local Hnmd = {}

local function to_num(v)
    local n = tonumber(v)
    if type(n) ~= "number" then return nil end
    return n
end

local function to_str(v)
    if v == nil then return nil end
    return tostring(v)
end

local function normalize_base_url(url)
    if type(url) ~= "string" or url == "" then
        return "https://hnmd.miguehm.com"
    end
    url = url:gsub("/+$", "")
    return url
end

local function normalize_item(item, idx)
    if type(item) ~= "table" then return nil end
    local id = to_str(item.id)
    if not id or id == "" then
        id = to_str(item.hn_id) or to_str(idx)
    end
    local status = to_str(item.status) or "ok"
    local markdown = to_str(item.markdown) or ""
    local view = {
        id = id,
        rank = to_num(item.rank) or idx,
        type = to_str(item.type) or "story",
        title = to_str(item.title) or "(untitled)",
        hn_url = to_str(item.hn_url) or "",
        url = item.url ~= nil and to_str(item.url) or nil,
        by = to_str(item.by) or "",
        score = to_num(item.score) or 0,
        descendants = to_num(item.descendants) or 0,
        published_at = to_str(item.published_at) or "",
        domain = to_str(item.domain) or "",
        markdown = markdown,
        status = status,
        error = item.error,
        scraped_at = to_str(item.scraped_at) or "",
        has_markdown = markdown ~= "",
    }
    return view
end

function Hnmd.fetch(config, opts)
    opts = opts or {}
    local base = normalize_base_url(config and config:get("hnmd_base_url"))
    local url = base .. "/top"
    local timeout_s = opts.timeout_s or (config and config:get("http_timeout_s")) or 10
    local max_bytes = opts.max_bytes or (config and config:get("http_max_bytes")) or 524288
    local api_key = config and config:get("hnmd_api_key") or ""

    local res = Http.get_json(url, {
        timeout_s = timeout_s,
        max_bytes = math.min(tonumber(max_bytes) or 524288, 524288),
        retries = 1,
        bearer_token = (type(api_key) == "string" and api_key ~= "") and api_key or nil,
        accept = "application/json",
    })

    if not res.ok then
        Logger.warn("hnmd", "fetch_failed", { kind = res.error_kind, status = res.status })
        return res
    end

    local data = res.json
    if type(data) ~= "table" then
        return { ok = false, error_kind = "parse", error = "invalid_response" }
    end

    local items_raw = data.items
    if type(items_raw) ~= "table" then
        return { ok = false, error_kind = "parse", error = "missing_items" }
    end

    local max_items = tonumber(config and config:get("hnmd_max_items")) or 10
    if max_items < 1 then max_items = 1 end
    if max_items > 20 then max_items = 20 end

    local normalized = {}
    for i, it in ipairs(items_raw) do
        local v = normalize_item(it, i)
        if v then table.insert(normalized, v) end
    end
    table.sort(normalized, function(a, b)
        local ra, rb = tonumber(a.rank) or 9999, tonumber(b.rank) or 9999
        if ra == rb then return tostring(a.id) < tostring(b.id) end
        return ra < rb
    end)
    while #normalized > max_items do
        table.remove(normalized)
    end

    local payload = {
        generated_at = data.generated_at,
        next_refresh_at = data.next_refresh_at,
        refresh_interval = data.refresh_interval,
        count = to_num(data.count) or #normalized,
        items = normalized,
        last_refresh_error = data.last_refresh_error,
        source_base_url = base,
    }

    Logger.info("hnmd", "fetch_ok", { count = #normalized, status = res.status })
    return {
        ok = true,
        status = res.status,
        payload = payload,
        fetched_at = os.time(),
    }
end

return Hnmd
