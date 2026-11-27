-- SPDX-License-Identifier: MIT
-- Smoke test: hnmd 1.5.0 offset pagination for /todos (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end

local plans, calls = {}, {}
package.preload["lib/http"] = function()
    return {
        get_json = function(url, opts)
            calls[#calls + 1] = { url = url, opts = opts }
            return table.remove(plans, 1)
        end,
    }
end

local Todos = dofile(PLUGIN .. "lib/todos.lua")
local config = {
    get = function(_, key)
        return ({ hnmd_base_url = "https://hnmd.example.com/v1", hnmd_api_key = "",
                  http_timeout_s = 6, http_max_bytes = 262144 })[key]
    end,
}

local function page(offset, ids, has_more, next_offset, truncated)
    local items = {}
    for _, id in ipairs(ids) do
        table.insert(items, { id = id, title = "Task " .. id, tags = {}, done = false, revision = 1 })
    end
    return {
        ok = true, status = 200,
        json = {
            schema_version = 1, counts = { open = 4, done = 0, total = 4 }, tags = {},
            offset = offset, limit = 2, returned_count = #ids,
            truncated = truncated and true or false,
            has_more = has_more and true or false, next_offset = next_offset,
            items = items,
        },
    }
end

local function reset()
    plans, calls = {}, {}
end

-- Follow next_offset, dedupe by id, preserve global counters.
reset()
plans = {
    page(0, { "a", "b" }, true, 2, true),
    page(2, { "b", "c" }, true, 4, false),
    page(4, { "d" }, false, nil, false),
}
local res = Todos.fetch_index(config, { status = "all" })
assert(res.ok, "paginated fetch failed")
assert(#calls == 3, "must follow every page")
assert(calls[1].url:sub(-#("offset=0")) == "offset=0", "first offset wrong")
assert(calls[2].url:sub(-#("offset=2")) == "offset=2", "second offset wrong")
assert(calls[3].url:sub(-#("offset=4")) == "offset=4", "third offset wrong")
assert(#res.payload.items == 4, "duplicate task id must be dropped")
assert(res.payload.items[1].id == "a" and res.payload.items[4].id == "d", "page order wrong")
assert(res.payload.returned_count == 4, "returned_count must reflect collected items")
assert(res.payload.counts.total == 4 and res.payload.has_more == false, "global counters lost")
assert(res.payload.offset == 0 and res.payload.limit == 2, "pagination metadata lost")
assert(res.payload.truncated == true and res.payload.partial == false, "byte-trim flag lost")

-- The page cap marks the list partial instead of fetching forever.
reset()
plans = {
    page(0, { "a", "b" }, true, 2, false),
    page(2, { "c" }, true, 4, false),
}
local capped = Todos.fetch_index(config, { status = "all", max_pages = 1 })
assert(capped.ok and capped.payload.partial == true, "page cap must mark the payload partial")
assert(capped.payload.has_more == true and #capped.payload.items == 2, "cap must stop after one page")
assert(#calls == 1, "cap must not issue a second request")

-- A failed later page keeps the first page as a partial, usable result.
reset()
plans = {
    page(0, { "a", "b" }, true, 2, false),
    { ok = false, status = 503, error_kind = "http_503" },
}
local partial = Todos.fetch_index(config, { status = "all" })
assert(partial.ok and partial.payload.partial == true and #partial.payload.items == 2,
    "a failed later page must keep earlier tasks")

-- A failed first page is still a hard failure.
reset()
plans = { { ok = false, status = 401, error_kind = "http_401" } }
local denied = Todos.fetch_index(config, { status = "all" })
assert(not denied.ok and denied.error_kind == "http_401", "first-page failure must propagate")

-- Local merges on a partial payload preserve the server's global counters and
-- apply only deterministic deltas; due counters are never recomputed locally.
reset()
local partial_payload = {
    counts = { open = 100, done = 5, total = 105, due_soon = 4, overdue = 2 },
    tags = { { tag = "casa", open = 3, done = 0, total = 3, due_soon = 2, overdue = 1 } },
    partial = true,
    items = { { id = "a", title = "A", tags = {}, done = false, revision = 1 } },
}
local merged = Todos.merge_payload(partial_payload, "create", {
    id = "b", title = "B", tags = {}, done = false, revision = 1,
})
assert(merged.counts.total == 106 and merged.counts.open == 101 and merged.counts.done == 5,
    "partial payload must apply only the write delta to global counters")
assert(merged.counts.due_soon == 4 and merged.counts.overdue == 2,
    "partial payload must not recompute due counters")
assert(merged.tags[1].due_soon == 2 and merged.tags[1].overdue == 1,
    "partial payload must not recompute per-tag due counters")
assert(merged.partial == true and #merged.items == 2, "partial flag must survive the merge")

print("OK todos pagination smoke: next_offset, dedupe, byte trim, caps, partial merges")
