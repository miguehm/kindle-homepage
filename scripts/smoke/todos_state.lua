-- SPDX-License-Identifier: MIT
-- Smoke test: todos cache-first state, TTL, invalidation and stale fallback.
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local calls = {}
local failure = nil
package.preload["lib/http"] = function()
    local function respond(url, opts)
        table.insert(calls, { url = url, opts = opts })
        if failure then return failure end
        if url:find("/todos/top", 1, true) then
            return {
                ok = true, status = 200,
                json = {
                    schema_version = 1, generated_at = "2026-11-22T14:00:00Z",
                    returned_count = 1, truncated = false,
                    items = { { id = "todos", rank = 1, type = "todo", title = "Todos (2 abiertas)",
                                hn_url = "https://example.com/v1/todos.md", content_status = "ok",
                                content_url = "/v1/todos.md", content_length = 100 } },
                },
            }
        end
        return {
            ok = true, status = 200,
            json = {
                schema_version = 1, generated_at = "2026-11-22T14:00:00Z",
                filter = { tag = nil, status = "all" },
                counts = { open = 2, done = 1, total = 3 },
                tags = {}, returned_count = 1, truncated = false,
                items = { { id = "a1", title = "Task", tags = { "casa" }, done = false, revision = 1 } },
            },
        }
    end
    return { get_json = respond }
end

local store = {}
local Cache = {}
function Cache:new(paths)
    local o = setmetatable({}, self)
    self.__index = self
    o.store = store
    return o
end
function Cache:read(name)
    local env = store[name]
    if not env then return nil, "missing" end
    return env
end
function Cache:is_expired(env, now)
    return (env.fetched_at + env.ttl_seconds) <= (now or os.time())
end
function Cache:write(name, opts)
    store[name] = {
        schema_version = 2,
        fetched_at = opts.fetched_at or os.time(),
        ttl_seconds = opts.ttl_seconds or 0,
        source = opts.source or name,
        status = opts.status or "ok",
        error = opts.error,
        payload = opts.payload,
    }
    return true
end
function Cache:mark_stale(env, kind, detail)
    env.status = "stale"
    env.error = { kind = kind or "unknown", detail = detail }
    return env
end
package.preload["lib/cache"] = function() return Cache end

local Refresh = dofile(PLUGIN .. "lib/refresh.lua")
package.preload["lib/refresh"] = function() return Refresh end

local TodosState = dofile(PLUGIN .. "lib/todos_state.lua")

local values = {
    hnmd_base_url = "https://example.com/v1",
    hnmd_api_key = "",
    http_timeout_s = 6,
    http_max_bytes = 262144,
    todos_enabled = true,
    todos_include_tags = true,
    todos_ttl_minutes = 5,
    refresh_budget_s = 20,
}
local config = { get = function(_, key) return values[key] end }
local paths = {}

local first = TodosState.load(config, paths, { allow_network = true })
assert(first.status == "ok" and first.payload.counts.open == 2, "first load failed")
assert(#calls == 1 and calls[1].url == "https://example.com/v1/todos?status=all", "fetch URL wrong")
assert(type(first.fetched_at) == "number", "fetched_at missing")

calls = {}
local cached = TodosState.load(config, paths, { allow_network = true })
assert(cached.status == "ok" and cached.from_cache == true, "cache hit failed")
assert(#calls == 0, "fresh cache must not hit the network")

assert(TodosState.load_top == nil, "the /todos/top index must no longer be used")
assert(store["todos_top.json"] == nil, "no todos_top cache must be written")

TodosState.invalidate(paths)
assert(store["todos.json"].status == "stale" and store["todos.json"].fetched_at == 0, "invalidate failed")

assert(TodosState.apply(paths, first.payload) == true, "local apply failed")
assert(store["todos.json"].status == "ok" and store["todos.json"].ttl_seconds == 0,
    "local apply must write a fresh but immediately refreshable envelope")
assert(store["todos.json"].payload.counts.open == 2, "local apply lost the payload")

calls = {}
failure = { ok = false, status = 401, error_kind = "http_401", body = "{}" }
local stale = TodosState.load(config, paths, { allow_network = true })
assert(stale.status == "stale" and stale.stale == true, "stale fallback failed")
assert(stale.payload and stale.payload.counts.open == 2, "stale payload lost")
assert(stale.error_kind == "http_401", "stale error kind lost")
assert(stale.message and stale.message ~= "", "stale message missing")

values.todos_enabled = false
local disabled = TodosState.load(config, paths, { allow_network = true })
assert(disabled.status == "disabled", "disabled guard failed")

print("OK todos state smoke: cache hit, no /todos/top, invalidation, stale fallback, disabled")
