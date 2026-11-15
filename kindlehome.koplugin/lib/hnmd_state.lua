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

local function status_message(err_kind, env_status)
    if err_kind == "http_401" then
        return "Invalid API key. Check Kindle Home HN settings."
    elseif err_kind == "http_503" then
        return "hnmd server is starting, try again in a few minutes."
    elseif err_kind == "offline" or err_kind == "timeout" or err_kind == "network" then
        return "Offline or network error. Showing cached HN if available."
    elseif err_kind == "parse" or err_kind == "too_large" then
        return "HN data error. Try refreshing."
    elseif err_kind == "budget_exceeded" then
        return "Refresh budget exceeded for HN."
    elseif env_status == "error" then
        return "HN unavailable."
    end
    return nil
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
            return Hnmd.fetch(config, {
                timeout_s = config:get("http_timeout_s"),
                max_bytes = config:get("http_max_bytes"),
            })
        end,
    })

    local env = res.envelope
    local payload = env and env.payload or nil
    local items = (payload and type(payload.items) == "table") and payload.items or {}
    local is_stale = res.stale or (env and env.status == "stale") or false
    local err_kind = res.error_kind or (env and env.error and env.error.kind) or nil
    local env_status = env and env.status or nil
    local msg = status_message(err_kind, env_status)

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

    if not msg then
        if err_kind == "http_401" then msg = "Invalid API key. Check Kindle Home HN settings."
        elseif err_kind == "http_503" then msg = "hnmd server is starting, try again in a few minutes."
        else msg = "HN unavailable." end
    end
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
