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
    todos_due_soon_days = 5,
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
    counts = { open = 2, done = 1, total = 3, due_soon = 1, overdue = 1 },
    tags = { { tag = "casa", open = 1, done = 0, total = 1, due_soon = 1, overdue = 0 } },
    returned_count = 2,
    truncated = false,
    items = {
        { id = "a1b2c3", title = "Comprar leche", tags = { "casa", "urgente" },
          details = "Llamar a la tienda\nAntes de las 18:00", due_date = "2026-11-30", done = false,
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
assert(index.payload.items[1].due_date == "2026-11-30", "due_date normalization failed")
assert(index.payload.items[2].due_date == nil, "missing due_date must stay nil")
assert(index.payload.counts.due_soon == 1 and index.payload.counts.overdue == 1,
    "due counts normalization failed")
assert(index.payload.tags[1].due_soon == 1, "tag due counts normalization failed")

reset()
next_json = { schema_version = 1, counts = {}, tags = {}, items = {} }
Todos.fetch_index(config, { status = "due_soon", due_days = 7 })
assert(last_call().url == "https://hnmd.miguehm.com/v1/todos?status=due_soon&due_days=7",
    "due_days must be sent to the API")

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
next_json = { id = "due1", title = "Tarea", tags = {}, details = "", due_date = "2026-11-30", done = false, revision = 1 }
local dated = Todos.create(config, "Tarea", nil, "", "2026-11-30")
assert(dated.ok and dated.task.due_date == "2026-11-30", "create with due date failed")
assert(last_call().opts.json_body.due_date == "2026-11-30", "create due date payload missing")
local bad_due = Todos.create(config, "x", nil, "", "30-11-2026")
assert(not bad_due.ok and bad_due.error_kind == "invalid_due_date", "invalid due date must be rejected")
assert(#calls == 1, "invalid due date must not reach transport")

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

reset()
next_json = { id = "new123", title = "Comprar leche", tags = { "casa" }, due_date = "2026-12-01", revision = 4 }
local due_patch = Todos.update(config, "new123", { due_date = "2026-12-01" })
assert(due_patch.ok and due_patch.task.due_date == "2026-12-01", "due patch failed")
assert(last_call().opts.json_body.due_date == "2026-12-01", "due patch payload missing")
Todos.update(config, "new123", { due_date = "" })
assert(last_call().opts.json_body.due_date == "", "clearing a due date must send an empty string")
local bad_due_patch = Todos.update(config, "new123", { due_date = "2026-02-30" })
assert(not bad_due_patch.ok and bad_due_patch.error_kind == "invalid_due_date",
    "invalid due date patch must be rejected")

reset()
local bad_id = Todos.update(config, "bad id", { done = true })
assert(not bad_id.ok and bad_id.error_kind == "parse", "invalid task id must be rejected")
assert(#calls == 0, "invalid task id must not reach transport")

reset()
local deleted = Todos.delete_task(config, "new123")
assert(deleted.ok and deleted.status == 200, "delete failed")
assert(last_call().opts.method == "DELETE", "delete method wrong")

local parsed = assert(Todos.parse_tags("#Casa, urgente casa"))
assert(#parsed == 2 and parsed[1] == "casa" and parsed[2] == "urgente", "tag parsing failed")
assert(#assert(Todos.parse_tags("")) == 0, "empty tag field must be valid")
assert(Todos.parse_tags("bad!tag") == nil, "invalid tag must be rejected")

reset()
next_json = { id = "new123", title = "Tarea", tags = {}, details = "", done = false, revision = 4 }
local tags_cleared = Todos.update(config, "new123", { tags = {} })
assert(tags_cleared.ok, "clearing tags failed")
assert(type(last_call().opts.json_body.tags) == "table"
    and #last_call().opts.json_body.tags == 0, "empty tags patch missing")
assert(last_call().opts.json_options and last_call().opts.json_options.empty_table_as_array == true,
    "empty tags must be encoded as a JSON array")

local payload = index.payload
local after_create = Todos.merge_payload(payload, "create", {
    id = "new1", title = "Nueva", tags = { "casa" }, done = false,
})
assert(#after_create.items == 3 and after_create.counts.open == 2
    and after_create.counts.done == 1 and after_create.counts.total == 3,
    "local create merge failed")
local after_update = Todos.merge_payload(after_create, "update", {
    id = "new1", title = "Nueva", tags = { "casa" }, done = true, done_at = "2026-11-22T15:00:00Z",
})
assert(#after_update.items == 3 and after_update.counts.done == 2
    and after_update.counts.open == 1, "local update merge failed")
local after_delete = Todos.merge_payload(after_update, "delete", nil, "new1")
assert(#after_delete.items == 2 and after_delete.counts.done == 1
    and after_delete.counts.open == 1, "local delete merge failed")
assert(#payload.items == 2, "merge must not mutate the source payload")

assert(Todos.format_due("2026-11-30") == "30-11-2026", "DD-MM-YYYY formatting failed")
assert(Todos.valid_due_date("2026-11-30") and not Todos.valid_due_date("30-11-2026"),
    "due date validation failed")
local bounds_now = os.time()
local today_iso, limit_iso = Todos.due_bounds(bounds_now, 3)
assert(Todos.classify_due("2000-01-01", today_iso, limit_iso) == "overdue",
    "overdue classification failed")
assert(Todos.classify_due(today_iso, today_iso, limit_iso) == "due_soon",
    "due soon classification failed")

local due_payload = { counts = { open = 0, done = 0, total = 0 }, tags = {}, items = {} }
local merged_due = Todos.merge_payload(due_payload, "create", {
    id = "d1", title = "Pronto", tags = { "casa" }, due_date = today_iso, done = false,
}, nil, { now = bounds_now, due_days = 3 })
assert(merged_due.counts.due_soon == 1 and merged_due.counts.overdue == 0
    and merged_due.tags[1].due_soon == 1, "local merge must recompute due counts")
local merged_late = Todos.merge_payload(due_payload, "create", {
    id = "d2", title = "Vencida", tags = {}, due_date = "2000-01-01", done = false,
}, nil, { now = bounds_now, due_days = 3 })
assert(merged_late.counts.overdue == 1, "local merge must recompute overdue counts")

print("OK todos client smoke: /todos JSON, due dates/filters, per-tag markdown URL, CRUD, details, tags, local merge, bearer, validation")
