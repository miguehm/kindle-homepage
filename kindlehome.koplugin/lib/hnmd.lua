local Http = require("lib/http")
local Logger = require("lib/logger")

-- hnmd client: the index carries metadata only; each article body is fetched
-- on demand as a Markdown file (see Hnmd.download_article).
local Hnmd = {}

Hnmd.API_VERSION = 1

local CONTENT_STATUS = {
    ok = true,
    no_content = true,
    warming_up = true,
    error = true,
}

local DEFAULT_BASE = "https://hnmd.miguehm.com/v1"

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
    if type(url) ~= "string" or url:match("^%s*$") then
        return DEFAULT_BASE
    end
    url = url:match("^%s*(.-)%s*$") or ""
    url = url:gsub("/+$", "")
    local rest = url:match("^https://(.+)$")
    if not rest or rest == "" then
        -- Never fall back to the default host with a user-supplied key: that
        -- would send the Bearer token somewhere the user did not configure.
        return nil
    end
    if not rest:find("/", 1, true) then
        url = url .. "/v1"
    end
    return url
end

-- Scheme + host[:port], used to resolve origin-absolute content URLs such as
-- "/v1/articles/123.md" without doubling the version prefix.
local function origin_of(base)
    return base:match("^(https://[^/]+)")
end

function Hnmd.resolve_content_url(base, content_url)
    base = normalize_base_url(base)
    if not base then
        return nil, "bad_base_url"
    end
    content_url = to_str(content_url)
    if not content_url or content_url == "" then
        return nil, "missing_content_url"
    end
    local origin = origin_of(base)
    if not origin then
        return nil, "bad_base_url"
    end
    if content_url:match("^%s*[%a][%w+.-]*:") then
        local abs_origin, abs_path = content_url:match("^(https://[^/]+)(/.*)$")
        if not abs_origin or not abs_path then
            return nil, "bad_content_url"
        end
        if abs_origin ~= origin then
            return nil, "cross_origin"
        end
        content_url = abs_path
    end
    if content_url:sub(1, 1) ~= "/" then
        -- Relative URLs are not part of the contract; resolve them against the
        -- base path rather than the origin so "/v1" is not lost.
        return base .. "/" .. content_url
    end
    return origin .. content_url
end

local function normalize_item(item, idx)
    if type(item) ~= "table" then return nil end
    local id = to_str(item.id)
    if not id or #id > 64 or not id:match("^[A-Za-z0-9_%-]+$") then
        return nil
    end
    local status = to_str(item.content_status) or "error"
    if not CONTENT_STATUS[status] then status = "error" end
    return {
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
        content_status = status,
        content_error = to_str(item.content_error),
        content_url = to_str(item.content_url),
        content_type = to_str(item.content_type),
        content_length = to_num(item.content_length),
        updated_at = to_str(item.updated_at),
    }
end

local function sorted_by_rank(items)
    table.sort(items, function(a, b)
        local ra, rb = tonumber(a.rank) or 9999, tonumber(b.rank) or 9999
        if ra == rb then return tostring(a.id) < tostring(b.id) end
        return ra < rb
    end)
    return items
end

local function clamp_items(n)
    n = tonumber(n) or 10
    if n < 1 then return 1 end
    if n > 20 then return 20 end
    return math.floor(n)
end

function Hnmd.fetch_index(config, opts)
    opts = opts or {}
    local base = normalize_base_url(config and config:get("hnmd_base_url"))
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    local max_items = clamp_items(config and config:get("hnmd_max_items"))
    local url = base .. "/top?limit=" .. tostring(max_items)
    local timeout_s = opts.timeout_s or (config and config:get("http_timeout_s")) or 10
    local max_bytes = opts.max_bytes or (config and config:get("index_max_bytes")) or 131072
    local api_key = config and config:get("hnmd_api_key") or ""

    local res = Http.get_json(url, {
        timeout_s = timeout_s,
        max_bytes = max_bytes,
        retries = 1,
        bearer_token = (type(api_key) == "string" and api_key ~= "") and api_key or nil,
        accept = "application/json",
    })

    if not res.ok then
        Logger.warn("hnmd", "index_failed", { kind = res.error_kind, status = res.status })
        return res
    end

    local data = res.json
    if type(data) ~= "table" then
        return { ok = false, error_kind = "parse", error = "invalid_response" }
    end
    if to_num(data.schema_version) ~= Hnmd.API_VERSION then
        return { ok = false, error_kind = "parse", error = "unsupported_schema" }
    end
    if type(data.items) ~= "table" then
        return { ok = false, error_kind = "parse", error = "missing_items" }
    end

    local normalized = {}
    for i, it in ipairs(data.items) do
        local v = normalize_item(it, i)
        if v then table.insert(normalized, v) end
    end
    sorted_by_rank(normalized)
    while #normalized > max_items do
        table.remove(normalized)
    end

    local payload = {
        schema_version = Hnmd.API_VERSION,
        generated_at = to_str(data.generated_at),
        next_refresh_at = to_str(data.next_refresh_at),
        refresh_interval_seconds = to_num(data.refresh_interval_seconds),
        returned_count = to_num(data.returned_count) or #normalized,
        truncated = data.truncated and true or false,
        items = normalized,
        source_base_url = base,
    }

    Logger.info("hnmd", "index_ok", { count = #normalized, status = res.status })
    return {
        ok = true,
        status = res.status,
        payload = payload,
        fetched_at = os.time(),
    }
end

-- Downloads the Markdown body to `tmp_path`. The caller owns the tmp file and
-- must promote it with rename once ok (atomic write). Errors keep their typed
-- error_kind so the UI can map them (http_401, http_404, too_large, ...).
function Hnmd.download_article(config, item, tmp_path, opts)
    opts = opts or {}
    if type(item) ~= "table" or not item.id then
        return { ok = false, error_kind = "parse", error = "invalid_item" }
    end
    local base = normalize_base_url(config and config:get("hnmd_base_url"))
    if not base then
        return { ok = false, error_kind = "parse", error = "bad_base_url" }
    end
    local url, resolve_err = Hnmd.resolve_content_url(base, item.content_url)
    if not url then
        return { ok = false, error_kind = "parse", error = resolve_err }
    end

    local timeout_s = opts.timeout_s or (config and config:get("http_timeout_s")) or 10
    local max_bytes = opts.max_bytes or (config and config:get("article_max_bytes")) or 524288
    local api_key = config and config:get("hnmd_api_key") or ""

    local res = Http.get_to_file(url, {
        path = tmp_path,
        timeout_s = timeout_s,
        max_bytes = max_bytes,
        retries = 1,
        bearer_token = (type(api_key) == "string" and api_key ~= "") and api_key or nil,
        accept = "text/markdown",
    })

    if not res.ok then
        Logger.warn("hnmd", "article_failed", { id = item.id, kind = res.error_kind, status = res.status })
        return res
    end

    local declared = tonumber(item.content_length)
    if declared and res.bytes ~= declared then
        pcall(os.remove, tmp_path)
        Logger.warn("hnmd", "article_length_mismatch", { id = item.id, expected = declared, got = res.bytes })
        return { ok = false, error_kind = "incomplete", error = "length_mismatch" }
    end

    local ctype = res.headers and res.headers["content-type"]
    if type(ctype) == "string" and not ctype:lower():find("text/markdown", 1, true) then
        -- Not fatal: some proxies rewrite the header. Keep the bytes we got.
        Logger.warn("hnmd", "unexpected_content_type", { id = item.id, ctype = ctype })
    end

    Logger.info("hnmd", "article_ok", { id = item.id, bytes = res.bytes })
    return res
end

return Hnmd
