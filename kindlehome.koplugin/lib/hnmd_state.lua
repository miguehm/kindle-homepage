-- SPDX-License-Identifier: MIT
local Cache = require("lib/cache")
local Logger = require("lib/logger")
local Refresh = require("lib/refresh")
local Hnmd = require("lib/hnmd")

local HnmdState = {}

local function fmt_age(fetched_at)
    if type(fetched_at) ~= "number" then return nil end
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M", fetched_at)
    if ok then return s end
    return nil
end

local Messages = require("ui/messages")

local function status_message(err_kind, env_status, has_cache)
    return Messages.hn(err_kind, env_status, has_cache)
end

function HnmdState.load(config, paths, opts)
    opts = opts or {}
    if not (config and config:get("hnmd_enabled")) then
        return { status = "disabled", line = "HN: disabled", items = {}, payload = nil }
    end

    local cache = Cache:new(paths)
    local ttl_seconds = math.max(60, (tonumber(config:get("hnmd_ttl_minutes")) or 30) * 60)
    local budget = opts.budget
    local res = Refresh.load_source(cache, {
        name = "hnmd.json",
        ttl_seconds = ttl_seconds,
        source = "hnmd",
        allow_network = opts.allow_network ~= false,
        budget = budget,
        fetch_fn = function()
            return Hnmd.fetch_index(config, {
                timeout_s = config:get("http_timeout_s"),
                max_bytes = config:get("index_max_bytes"),
            })
        end,
    })

    local env = res.envelope
    local payload = env and env.payload or nil
    local items = (payload and type(payload.items) == "table") and payload.items or {}
    local is_stale = res.stale or (env and env.status == "stale") or false
    local err_kind = res.error_kind or (env and env.error and env.error.kind) or nil
    local env_status = env and env.status or nil
    local msg = status_message(err_kind, env_status, #items > 0)

    if #items > 0 or (payload and type(payload) == "table") then
        local status = "ok"
        if is_stale then status = "stale" end
        if env_status == "error" and #items == 0 then status = "error" end
        local line = string.format("HN: %d item(s)", #items)
        if msg then line = msg end
        if status == "stale" and not msg then
            line = string.format("HN: showing cached %d item(s).", #items)
        end
        return {
            status = status,
            line = line,
            items = items,
            payload = payload,
            fetched_at = env and env.fetched_at or (payload and payload.fetched_at),
            generated_at = payload and payload.generated_at or nil,
            next_refresh_at = payload and payload.next_refresh_at or nil,
            last_refresh_error = payload and payload.last_refresh_error or nil,
            stale = is_stale,
            error_kind = err_kind,
            from_cache = res.from_cache,
            message = msg,
        }
    end

    if not msg then msg = Messages.hn(err_kind, "error", false) or "HN unavailable." end
    Logger.warn("hnmd_state", "unavailable", { kind = err_kind })
    return {
        status = "error",
        line = msg,
        items = {},
        payload = payload,
        fetched_at = env and env.fetched_at or nil,
        stale = is_stale,
        error_kind = err_kind,
        from_cache = res.from_cache,
        message = msg,
    }
end

return HnmdState
