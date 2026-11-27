-- SPDX-License-Identifier: MIT
-- Smoke test: hnmd 1.5.0 ETag revalidation and /v1/status client (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local plans, calls = {}, {}
package.preload["lib/http"] = function()
    return {
        get_json = function(url, opts)
            calls[#calls + 1] = { url = url, opts = opts }
            return table.remove(plans, 1) or { ok = false, error_kind = "network" }
        end,
        get_to_file = function() return { ok = false } end,
    }
end

local Hnmd = dofile(PLUGIN .. "lib/hnmd.lua")

-- Refresh has no need for the real filesystem/cache in this smoke.
local store = {}
local Cache = {}
Cache.__index = Cache
function Cache:new() return setmetatable({ store = store }, self) end
function Cache:read(name) return self.store[name] end
function Cache:is_expired() return true end
function Cache:mark_stale(env) return env end
function Cache:write(name, opts) self.store[name] = opts; return true end
package.preload["lib/cache"] = function() return Cache end

local Refresh = dofile(PLUGIN .. "lib/refresh.lua")
local config = {
    get = function(_, key)
        return ({ hnmd_base_url = "https://hnmd.example.com/v1", hnmd_api_key = "secret",
                  http_timeout_s = 6, index_max_bytes = 131072, hnmd_max_items = 20 })[key]
    end,
}

local function reset()
    plans, calls = {}, {}
end

local function index_page(offset)
    return {
        ok = true, status = 200, headers = { etag = 'W/"v2"' },
        json = {
            schema_version = 1, generated_at = "2026-11-26T00:00:00Z",
            offset = offset, limit = 20, returned_count = 1,
            has_more = false, next_offset = nil, truncated = false,
            items = { { id = "1", rank = 1, title = "Story", content_status = "ok",
                        content_url = "/v1/articles/1.md" } },
        },
    }
end

-- 304 keeps the cache untouched and never tries to decode a body.
reset()
plans = { { ok = true, status = 304, not_modified = true, headers = { etag = 'W/"v1"' } } }
local revalidated = Hnmd.fetch_index(config, { etag = 'W/"v1"' })
assert(revalidated.ok and revalidated.not_modified and revalidated.status == 304,
    "304 must be a successful revalidation")
assert(revalidated.payload == nil, "304 must not replace the cached payload")
assert(calls[1].opts.if_none_match == 'W/"v1"', "If-None-Match not sent")
assert(calls[1].url:sub(-#("/top?limit=20")) == "/top?limit=20", "top URL changed")

-- A 200 carries a fresh weak validator back to the cache layer.
reset()
plans = { index_page(0) }
local fresh = Hnmd.fetch_index(config, {})
assert(fresh.ok and fresh.etag == 'W/"v2"', "ETag must be captured from the response")
assert(fresh.payload.offset == 0 and fresh.payload.has_more == false, "pagination fields missing")

-- Refresh.load_source updates the timestamp but preserves the cached payload.
store["hnmd.json"] = {
    schema_version = 2, fetched_at = 100, ttl_seconds = 1800,
    source = "hnmd", status = "ok", etag = 'W/"v1"',
    payload = { items = { { id = "kept" } } },
}
local cache = Cache:new()
local loaded = Refresh.load_source(cache, {
    name = "hnmd.json", ttl_seconds = 1800, source = "hnmd",
    fetch_fn = function(cached)
        assert(cached and cached.etag == 'W/"v1"', "fetch_fn must receive the cached envelope")
        return { ok = true, not_modified = true }
    end,
})
assert(loaded.ok and loaded.revalidated and loaded.from_cache, "revalidation must be cache-first")
assert(loaded.envelope.payload.items[1].id == "kept", "304 must keep the cached payload")
assert(loaded.envelope.fetched_at > 100, "304 must refresh fetched_at")
assert(store["hnmd.json"].etag == 'W/"v1"', "304 must keep the validator")

-- /v1/status is parsed into non-sensitive metadata.
reset()
plans = { {
    ok = true, status = 200,
    json = { schema_version = 1, version = "1.5.0", ready = true, auth_enabled = true,
             todo_count = 7, server_time = "2026-11-26T00:00:00Z" },
} }
local status = Hnmd.fetch_status(config)
assert(status.ok and status.payload.version == "1.5.0"
    and status.payload.todo_count == 7 and status.payload.ready == true, "status parsing failed")
assert(calls[1].url:sub(-#("/status")) == "/status", "status URL wrong")
assert(calls[1].opts.bearer_token == "secret", "status must carry the bearer key")

print("OK hnmd conditional smoke: ETag/304 revalidation, cached payload, /status")
