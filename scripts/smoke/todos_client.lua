-- SPDX-License-Identifier: MIT
-- Smoke test: hnmd /todos/top client and the todos JSON/CRUD client (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local calls = {}
local next_json = {}
local next_failure = nil
package.preload["lib/http"] = function()
    local function respond(url, opts)
        table.insert(calls, { url = url, opts = opts })
        if next_failure then return next_failure end
        return { ok = true, status = 200, body = "{}", json = next_json }
    end
    return {
        get_json = respond,
        request_json = respond,
        request = respond,
    }
end

local Hnmd = dofile(PLUGIN .. "lib/hnmd.lua")
local Todos = dofile(PLUGIN .. "lib/todos.lua")

local cfg_values = {
    hnmd_base_url = "https://hnmd.miguehm.com/v1",
    hnmd_api_key = "key-1234567890",
    http_timeout_s = 6,
    http_max_bytes = 262144,
    index_max_bytes = 131072,
    hnmd_max_items = 10,
}
local config = { get = function(_, key) return cfg_values[key] end }

local function last_call()
    return calls[#calls]
end

local function reset()
    calls = {}
    next_failure = nil
    next_json = {}
end

reset()
assert(Hnmd.fetch_todos_index == nil, "the /todos/top index must no longer be used")
assert(Hnmd.fetch_index and type(Hnmd.fetch_index) == "function", "legacy /top client must survive")
assert(Hnmd.resolve_content_url(cfg_values.hnmd_base_url, "/v1/todos/tags/casa.md")
    == "https://hnmd.miguehm.com/v1/todos/tags/casa.md", "per-tag markdown URL resolution failed")

reset()
next_json = {
    schema_version = 1,
    generated_at = "2026-11-22T14:00:00Z",
    filter = { tag = nil, status = "all" },
    counts = { open = 2, done = 1, total = 3 },
    tags = { { tag = "casa", open = 1, done = 0, total = 1 } },
    returned_count = 2,
    truncated = false,
    items = {
        { id = "a1b2c3", title = "Comprar leche", tags = { "casa", "urgente" },
          details = "Llamar a la tienda\nAntes de las 18:00", done = false,
          created_at = "2026-11-22T13:00:00Z", updated_at = "2026-11-22T13:00:00Z", revision = 1 },
        { id = "d4e5f6", title = "Pagar", tags = {}, done = true, revision = 2 },
    },
}
local index = Todos.fetch_index(config, { status = "all" })
assert(index.ok, "todos index failed")
assert(last_call().url == "https://hnmd.miguehm.com/v1/todos?status=all", "todos index URL wrong")
assert(index.payload.counts.open == 2 and #index.payload.tags == 1, "counts/tags normalization failed")
assert(#index.payload.items == 2 and index.payload.items[1].tags[1] == "casa", "tasks normalization failed")
assert(index.payload.items[1].details == "Llamar a la tienda\nAntes de las 18:00", "details normalization failed")
assert(index.payload.items[2].details == "", "missing details must normalize to empty string")
assert(index.payload.items[2].done == true, "done normalization failed")

reset()
next_json = { schema_version = 99, items = {} }
local bad_schema = Todos.fetch_index(config)
assert(not bad_schema.ok and bad_schema.error_kind == "parse", "schema rejection failed")

reset()
next_failure = { ok = false, status = 401, error_kind = "http_401", body = '{"error":"unauthorized"}' }
local denied = Todos.fetch_index(config)
assert(not denied.ok and denied.error_kind == "http_401", "401 propagation failed")

reset()
next_json = { id = "new123", title = "Comprar leche", tags = { "casa" }, details = "nota", done = false, revision = 1 }
local created = Todos.create(config, "Comprar leche #casa", { "urgente" }, "nota")
assert(created.ok and created.task.id == "new123" and created.task.details == "nota", "create failed")
assert(last_call().url == "https://hnmd.miguehm.com/v1/todos/tasks", "create URL wrong")
assert(last_call().opts.method == "POST" and last_call().opts.retries == 0, "create method/retry wrong")
assert(last_call().opts.json_body.text == "Comprar leche #casa", "create text missing")
assert(last_call().opts.json_body.details == "nota", "create details missing")
assert(last_call().opts.bearer_token == cfg_values.hnmd_api_key, "create bearer missing")

local bad_details = Todos.create(config, "x", nil, string.rep("x", 1001))
assert(not bad_details.ok and bad_details.error_kind == "parse", "oversized details must be rejected")
assert(#calls == 1, "oversized details must not reach transport")

reset()
next_json = { id = "new123", title = "Comprar leche", tags = { "casa" }, done = true, revision = 2 }
local updated = Todos.update(config, "new123", { done = true })
assert(updated.ok and updated.task.done == true, "update failed")
assert(last_call().opts.method == "PATCH", "update method wrong")
assert(last_call().url == "https://hnmd.miguehm.com/v1/todos/tasks/new123", "update URL wrong")
assert(last_call().opts.json_body.done == true, "update payload wrong")

reset()
next_json = { id = "new123", title = "Comprar leche", tags = { "casa" }, details = "", revision = 3 }
local cleared = Todos.update(config, "new123", { details = "" })
assert(cleared.ok and cleared.task.details == "", "details patch failed")
assert(last_call().opts.json_body.details == "", "details patch payload missing")

local bad_id = Todos.update(config, "bad id", { done = true })
assert(not bad_id.ok and bad_id.error_kind == "parse", "invalid task id must be rejected")
assert(#calls == 1, "invalid task id must not reach transport")

reset()
local deleted = Todos.delete_task(config, "new123")
assert(deleted.ok and deleted.status == 200, "delete failed")
assert(last_call().opts.method == "DELETE", "delete method wrong")

print("OK todos client smoke: /todos JSON, per-tag markdown URL, CRUD, details, bearer, validation")
