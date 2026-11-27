-- SPDX-License-Identifier: MIT
-- Smoke test: hnmd 1.5.0 If-Match writes and conflict classification (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local calls, next_json, next_failure = {}, {}, nil
package.preload["lib/http"] = function()
    local function respond(url, opts)
        calls[#calls + 1] = { url = url, opts = opts }
        return next_failure or { ok = true, status = 200, json = next_json }
    end
    return { get_json = respond, request_json = respond, request = respond }
end

local Todos = dofile(PLUGIN .. "lib/todos.lua")
local Messages = dofile(PLUGIN .. "ui/messages.lua")

local config = {
    get = function(_, key)
        return ({ hnmd_base_url = "https://hnmd.example.com/v1", hnmd_api_key = "secret",
                  http_timeout_s = 6, http_max_bytes = 262144 })[key]
    end,
}

local function reset()
    calls, next_json, next_failure = {}, {}, nil
end

local function failure(status, fields)
    local res = { ok = false, status = status, error_kind = "http_other", body = "" }
    for k, v in pairs(fields or {}) do res[k] = v end
    return res
end

-- Every write carries the stored revision as a strong validator.
reset()
next_json = { id = "abc", title = "Task", tags = {}, done = true, revision = 2 }
local updated = Todos.update(config, "abc", { done = true }, { revision = 1 })
assert(updated.ok, "update should succeed")
assert(calls[1].opts.if_match == '"1"', "PATCH must send If-Match: \"revision\"")
assert(calls[1].opts.bearer_token == "secret", "bearer token must be present")

reset()
local deleted = Todos.delete_task(config, "abc", { revision = 7 })
assert(deleted.ok, "delete should succeed")
assert(calls[1].opts.method == "DELETE" and calls[1].opts.if_match == '"7"',
    "DELETE must send If-Match")
assert(calls[1].opts.body == "", "DELETE body must be empty")

-- Missing revision fails locally instead of provoking a guaranteed 428.
reset()
local missing = Todos.update(config, "abc", { done = true })
assert(not missing.ok and missing.error_kind == "missing_revision", "missing revision guard failed")
assert(#calls == 0, "missing revision must not reach transport")

-- 412/428 are typed, never retried, and produce actionable UI messages.
reset()
next_failure = failure(412, {
    error_kind = "revision_conflict", error_code = "revision_conflict",
    current_revision = 9,
})
local conflict = Todos.update(config, "abc", { done = true }, { revision = 8 })
assert(not conflict.ok and conflict.error_kind == "revision_conflict"
    and conflict.current_revision == 9, "412 classification failed")
assert(#calls == 1, "412 must not be retried")
assert(Messages.todos_write(conflict):find("refreshed", 1, true) ~= nil,
    "412 needs an actionable message")

reset()
next_failure = failure(428, { error_kind = "precondition_required",
    error_code = "precondition_required", error_field = "if_match" })
local required = Todos.delete_task(config, "abc", { revision = 1 })
assert(not required.ok and required.error_kind == "precondition_required", "428 classification failed")
assert(#calls == 1, "428 must not be retried")
assert(Messages.todos_write(required) ~= nil, "428 needs an actionable message")

reset()
next_failure = failure(403, { error_kind = "forbidden", error_code = "forbidden" })
local forbidden = Todos.update(config, "abc", { done = true }, { revision = 1 })
assert(forbidden.error_kind == "forbidden" and Messages.todos_write(forbidden) ~= nil,
    "403 must map to the write-permission message")

-- Unified error shapes: field names drive validation messages.
local cases = {
    { field = "due_date", kind = "invalid_due_date" },
    { field = "tags", kind = "invalid_tags" },
    { field = "details", kind = "invalid_details" },
    { field = "tz", kind = "invalid_timezone" },
}
for _, case in ipairs(cases) do
    reset()
    next_failure = failure(400, {
        error_kind = "http_other", error_code = "invalid_request", error_field = case.field,
    })
    local bad = Todos.create(config, "Task")
    assert(bad.error_kind == case.kind, "field " .. case.field .. " was not mapped")
    assert(Messages.todos_write(bad) ~= nil, "field " .. case.field .. " needs a message")
end

print("OK todos conflict smoke: If-Match, 412/428/403, unified error fields")
