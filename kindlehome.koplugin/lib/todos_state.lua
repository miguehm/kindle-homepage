-- SPDX-License-Identifier: MIT
local Cache = require("lib/cache")
local Logger = require("lib/logger")
local Messages = require("ui/messages")
local Refresh = require("lib/refresh")
local Todos = require("lib/todos")

local TodosState = {}

local function counts_of(payload)
    payload = payload or {}
    return payload.counts or {}
end

local function build_line(payload, is_stale)
    local counts = counts_of(payload)
    local line = string.format("TODO'S — %d open, %d done", counts.open or 0, counts.done or 0)
    if is_stale then line = line .. " (stale)" end
    return line
end

local function finish(res, source)
    local env = res.envelope
    local payload = env and env.payload or nil
    local is_stale = res.stale or (env and env.status == "stale") or false
    local err_kind = res.error_kind or (env and env.error and env.error.kind) or nil
    local fetched_at = env and env.fetched_at or nil

    if payload and type(payload) == "table" then
        return {
            status = is_stale and "stale" or "ok",
            line = build_line(payload, is_stale),
            payload = payload,
            fetched_at = fetched_at,
            stale = is_stale,
            error_kind = err_kind,
            from_cache = res.from_cache,
            message = is_stale and Messages.for_kind(err_kind) or nil,
        }
    end

    local msg = Messages.todos(err_kind, "error")
    Logger.warn("todos_state", "unavailable", { source = source, kind = err_kind })
    return {
        status = "error",
        line = msg,
        message = msg,
        payload = nil,
        fetched_at = fetched_at,
        stale = is_stale,
        error_kind = err_kind,
        from_cache = res.from_cache,
    }
end

local function ttl_seconds(config)
    return math.max(60, (tonumber(config:get("todos_ttl_minutes")) or 5) * 60)
end

function TodosState.load(config, paths, opts)
    opts = opts or {}
    local enabled = config and config:get("todos_enabled")
    if enabled == false then
        return { status = "disabled", line = "TODO'S: disabled", payload = nil }
    end
    local cache = Cache:new(paths)
    local res = Refresh.load_source(cache, {
        name = "todos.json",
        ttl_seconds = ttl_seconds(config),
        source = "todos",
        allow_network = opts.allow_network ~= false,
        budget = opts.budget,
        fetch_fn = function()
            return Todos.fetch_index(config, { status = "all" })
        end,
    })
    return finish(res, "todos")
end

function TodosState.invalidate(paths)
    local cache = Cache:new(paths)
    for _, name in ipairs({ "todos.json" }) do
        local env = cache:read(name)
        if env then
            cache:write(name, {
                fetched_at = 0,
                ttl_seconds = 0,
                source = env.source or name,
                status = "stale",
                error = { kind = "invalidated", detail = "local_write" },
                payload = env.payload,
            })
        end
    end
end

return TodosState
