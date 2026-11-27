-- SPDX-License-Identifier: MIT
local Cache = require("lib/cache")
local Logger = require("lib/logger")

local Refresh = {}

local in_progress = false

local function now_epoch()
    return os.time()
end

function Refresh.is_in_progress()
    return in_progress
end

function Refresh.begin()
    if in_progress then
        return false
    end
    in_progress = true
    return true
end

function Refresh.finish()
    in_progress = false
end

-- Cache-first load helper for a single source.
-- opts: { name, ttl_seconds, source, fetch_fn, allow_network, budget }
-- budget: { deadline = epoch_seconds } (optional)
function Refresh.load_source(cache, opts)
    opts = opts or {}
    local name = opts.name
    local ttl = tonumber(opts.ttl_seconds) or 0
    local source = opts.source or name or "unknown"
    local allow_network = opts.allow_network ~= false
    local budget = opts.budget

    local cached, read_err = cache:read(name)
    local expired = true
    if cached then
        expired = cache:is_expired(cached) and true or false
    end

    if cached and not expired then
        return { ok = true, from_cache = true, stale = cached.status == "stale", envelope = cached }
    end

    if not allow_network or type(opts.fetch_fn) ~= "function" then
        if cached then
            Logger.info("refresh", "cache_fallback", { source = source, reason = "offline_or_no_fetch" })
            local env = cache:mark_stale(cached, "offline", read_err)
            return { ok = true, from_cache = true, stale = true, envelope = env, error_kind = "offline" }
        end
        return { ok = false, from_cache = false, stale = false, error_kind = "offline", error = "no cache and network disabled" }
    end

    if budget and budget.deadline and now_epoch() >= budget.deadline then
        if cached then
            local env = cache:mark_stale(cached, "budget_exceeded", "refresh budget exceeded")
            return { ok = true, from_cache = true, stale = true, envelope = env, error_kind = "budget_exceeded" }
        end
        return { ok = false, error_kind = "budget_exceeded", error = "refresh budget exceeded" }
    end

    local ok_fetch, fetch_res = pcall(opts.fetch_fn, cached)
    if not ok_fetch then
        Logger.warn("refresh", "fetch_exception", { source = source, err = tostring(fetch_res) })
        if cached then
            local env = cache:mark_stale(cached, "exception", tostring(fetch_res))
            pcall(cache.write, cache, name, { ttl_seconds = ttl, source = source, status = "stale", error = env.error, payload = env.payload, fetched_at = env.fetched_at })
            return { ok = true, from_cache = true, stale = true, envelope = env, error_kind = "exception" }
        end
        return { ok = false, error_kind = "exception", error = tostring(fetch_res) }
    end

    -- A 304 means the cached body is still current. Refresh only its timestamp
    -- and TTL so the next decision is made from a fresh age, never dropping
    -- the payload (hnmd 1.5.0 migration rule).
    if fetch_res and fetch_res.not_modified then
        if not cached then
            return { ok = false, from_cache = false, stale = false,
                     error_kind = "unexpected_not_modified", error = "304 without cached payload" }
        end
        cached.fetched_at = opts.fetched_at or now_epoch()
        cache:write(name, {
            ttl_seconds = ttl,
            source = source,
            status = cached.status == "error" and "ok" or cached.status,
            error = cached.error,
            etag = cached.etag,
            payload = cached.payload,
            fetched_at = cached.fetched_at,
        })
        local env = cache:read(name)
        return {
            ok = true, from_cache = true, stale = false, revalidated = true,
            envelope = env or cached,
        }
    end

    if fetch_res and fetch_res.ok then
        local envelope_opts = {
            ttl_seconds = ttl,
            source = source,
            status = "ok",
            payload = fetch_res.payload or fetch_res.json or fetch_res.body,
            fetched_at = fetch_res.fetched_at or now_epoch(),
            etag = fetch_res.etag,
        }
        cache:write(name, envelope_opts)
        local env = cache:read(name)
        return { ok = true, from_cache = false, stale = false, envelope = env or envelope_opts }
    end

    local err_kind = (fetch_res and (fetch_res.error_kind or fetch_res.error)) or "fetch_failed"
    if cached then
        local env = cache:mark_stale(cached, err_kind, fetch_res and fetch_res.error)
        pcall(cache.write, cache, name, { ttl_seconds = ttl, source = source, status = "stale", error = env.error, payload = env.payload, fetched_at = env.fetched_at })
        return { ok = true, from_cache = true, stale = true, envelope = env, error_kind = err_kind }
    end

    cache:write(name, { ttl_seconds = ttl, source = source, status = "error", error = { kind = err_kind, detail = fetch_res and fetch_res.error }, payload = nil })
    local env = cache:read(name)
    return { ok = false, from_cache = false, stale = false, envelope = env, error_kind = err_kind }
end

function Refresh.new_budget(seconds)
    local s = tonumber(seconds) or 0
    if s <= 0 then return nil end
    return { deadline = now_epoch() + math.floor(s) }
end

return Refresh
