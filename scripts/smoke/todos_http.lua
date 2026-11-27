-- SPDX-License-Identifier: MIT
-- Smoke test: Http write methods (Lua 5.1) with socket.http stubbed.
-- Covers POST/PATCH/DELETE, typed errors, 401/403, byte caps and retry policy.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local logged = {}
package.preload["lib/logger"] = function()
    local function record(level, module_name, event, details)
        local line = "module=" .. tostring(module_name) .. " event=" .. tostring(event)
        for k, v in pairs(details or {}) do line = line .. " " .. k .. "=" .. tostring(v) end
        table.insert(logged, line)
    end
    return { info = record, warn = record, err = record }
end
package.preload["socket"] = function()
    return { gettime = function() return 100 + os.clock() end }
end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end }
end
package.preload["ltn12"] = function()
    return {
        sink = {
            table = function(tbl)
                return function(chunk)
                    if chunk then tbl[#tbl + 1] = chunk end
                    return 1
                end
            end,
        },
        source = {
            string = function(text)
                local sent = false
                return function()
                    if sent then return nil end
                    sent = true
                    return text
                end
            end,
        },
    }
end
local next_decode = {}
package.preload["rapidjson"] = function()
    return {
        encode = function() return '{"text":"Comprar leche #casa"}' end,
        decode = function() return next_decode end,
    }
end

local plans = {}
local requests = {}
package.preload["socket.http"] = function()
    return {
        request = function(req)
            table.insert(requests, req)
            local plan = table.remove(plans, 1) or { code = 500 }
            if plan.transport then return nil, plan.transport end
            for _, chunk in ipairs(plan.chunks or {}) do
                local ok, err = req.sink(chunk)
                if not ok then return nil, err end
            end
            req.sink(nil)
            return 1, plan.code or 200, plan.headers or {}, "HTTP/1.1 " .. tostring(plan.code or 200)
        end,
    }
end

local Http = dofile(PLUGIN .. "lib/http.lua")
local SECRET = "super-secret-key-1234"
local opts = { bearer_token = SECRET, timeout_s = 2, max_bytes = 4096 }

local function last_request()
    return requests[#requests]
end

local function reset()
    requests, logged = {}, {}
end

reset()
plans = { { code = 201, chunks = { '{"id":"abc"}' }, headers = { location = "/v1/todos/tasks/abc" } } }
next_decode = { id = "abc" }
local created = Http.post_json("https://example.com/v1/todos/tasks", { text = "Comprar leche #casa" }, opts)
assert(created.ok and created.status == 201 and created.json.id == "abc", "POST 201 failed")
assert(last_request().method == "POST", "POST method missing")
assert(last_request().headers["content-type"] == "application/json", "POST content-type missing")
assert(last_request().headers["authorization"] == "Bearer " .. SECRET, "POST bearer missing")
local body = last_request().source()
assert(body and body:find("Comprar leche", 1, true), "POST body missing")
assert(#requests == 1, "POST must not retry")

reset()
plans = { { code = 401, chunks = { '{"error":"unauthorized"}' }, headers = {} } }
local denied = Http.post_json("https://example.com/v1/todos/tasks", { text = "x" }, opts)
assert(not denied.ok and denied.error_kind == "http_401", "POST 401 mapping failed")
assert(#requests == 1, "401 must never be retried")

reset()
plans = { { code = 403, chunks = { '{"error":"forbidden"}' }, headers = {} } }
local forbidden = Http.patch_json("https://example.com/v1/todos/tasks/abc", { done = true }, opts)
assert(not forbidden.ok and forbidden.status == 403 and forbidden.error_kind == "forbidden", "PATCH 403 mapping failed")
assert(last_request().method == "PATCH", "PATCH method missing")
assert(last_request().headers["accept-encoding"] == "identity", "gzip must not be negotiated")

reset()
plans = { { code = 428, chunks = { '{"error":"precondition_required","message":"If-Match header is required","field":"if_match"}' }, headers = {} } }
next_decode = { error = "precondition_required", field = "if_match" }
local missing_match = Http.patch_json("https://example.com/v1/todos/tasks/abc", { done = true }, opts)
assert(not missing_match.ok and missing_match.error_kind == "precondition_required"
    and missing_match.error_code == "precondition_required" and missing_match.error_field == "if_match",
    "PATCH 428 mapping failed")
assert(#requests == 1, "428 must never be retried")

reset()
plans = { { code = 412, chunks = { '{"error":"revision_conflict","message":"task revision does not match","current_revision":3}' }, headers = {} } }
next_decode = { error = "revision_conflict", current_revision = 3 }
local conflict = Http.patch_json("https://example.com/v1/todos/tasks/abc", { done = true }, opts)
assert(not conflict.ok and conflict.error_kind == "revision_conflict"
    and conflict.current_revision == 3, "PATCH 412 mapping failed")
assert(conflict.json and conflict.json.current_revision == 3, "error JSON must be parsed on failure")
assert(#requests == 1, "412 must never be retried")

reset()
plans = { { code = 204, chunks = {}, headers = {} } }
local deleted = Http.delete("https://example.com/v1/todos/tasks/abc", opts)
assert(deleted.ok and deleted.status == 204, "DELETE 204 failed")
assert(last_request().method == "DELETE", "DELETE method missing")

reset()
plans = { { transport = "timeout" }, { code = 200, chunks = { "{}" }, headers = {} }, }
next_decode = {}
local retried = Http.patch_json("https://example.com/v1/todos/tasks/abc", { done = true }, {
    bearer_token = SECRET, retries = 1,
})
assert(retried.ok and #requests == 2, "transient PATCH retry failed")

reset()
plans = { { chunks = { string.rep("x", 5000) }, code = 200, headers = {} } }
local too_large = Http.patch_json("https://example.com/v1/todos/tasks/abc", { done = true }, {
    bearer_token = SECRET, max_bytes = 64,
})
assert(not too_large.ok and too_large.error_kind == "too_large", "write response cap failed")

reset()
local req_body_too_large = Http.post_json("https://example.com/v1/todos/tasks", { text = string.rep("x", 100) }, {
    bearer_token = SECRET, max_request_bytes = 8,
})
assert(not req_body_too_large.ok and req_body_too_large.error_kind == "too_large", "write request cap failed")
assert(#requests == 0, "invalid request must not reach transport")

for _, line in ipairs(logged) do
    assert(not line:find(SECRET, 1, true), "API key leaked into logs: " .. line)
    assert(not line:find("Comprar leche", 1, true), "payload leaked into logs: " .. line)
end

print("OK todos http smoke: POST/PATCH/DELETE, 401/403, transient retry, caps, no secrets")
