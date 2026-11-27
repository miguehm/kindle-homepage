-- SPDX-License-Identifier: MIT
-- Smoke test: conditional reads (If-None-Match / 304) and gzip policy (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["socket"] = function()
    return { gettime = function() return os.time() end }
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
    }
end
local next_decode = {}
package.preload["rapidjson"] = function()
    return { decode = function() return next_decode end }
end

local plans, requests = {}, {}
package.preload["socket.http"] = function()
    return {
        request = function(req)
            requests[#requests + 1] = req
            local plan = table.remove(plans, 1) or { code = 500 }
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

local last = function() return requests[#requests] end

-- 304 is a successful revalidation, never an error, never retried.
plans = { { code = 304, headers = { etag = 'W/"a1b2"' } } }
local res = Http.get_json("https://example.com/v1/top", {
    if_none_match = 'W/"a1b2"', retries = 2,
})
assert(res.ok and res.not_modified and res.status == 304, "304 must be ok/not_modified")
assert(res.json == nil, "304 must not expose a decoded body")
assert(#requests == 1, "304 must never be retried")
assert(last().headers["if-none-match"] == 'W/"a1b2"', "If-None-Match header missing")
assert(last().headers["accept-encoding"] == "identity", "gzip must not be negotiated")

-- A normal 200 still decodes JSON and exposes the validator to the caller.
next_decode = { schema_version = 1, items = {} }
plans = { { code = 200, chunks = { '{"schema_version":1,"items":[]}' },
            headers = { etag = 'W/"new"' } } }
res = Http.get_json("https://example.com/v1/top", {})
assert(res.ok and not res.not_modified and res.json.schema_version == 1, "200 JSON failed")
assert(res.headers.etag == 'W/"new"', "ETag header must be readable")

-- Streaming 304 drops the temp file; the canonical copy is owned by the
-- caller, so it must remain byte-for-byte intact.
local canonical = os.tmpname()
local f = io.open(canonical, "wb")
assert(f, "cannot create temp file")
f:write("old body")
f:close()
local tmp_path = canonical .. ".tmp"
plans = { { code = 304, headers = {} } }
res = Http.get_to_file("https://example.com/v1/articles/1.md", {
    path = tmp_path, if_none_match = 'W/"old"',
})
assert(res.ok and res.not_modified and res.status == 304, "file 304 must be ok/not_modified")
local leftover = io.open(tmp_path, "rb")
if leftover then leftover:close() end
assert(leftover == nil, "304 must remove the empty temp file")
local reread = io.open(canonical, "rb")
assert(reread, "canonical copy must survive a 304")
local content = reread:read("*a")
reread:close()
assert(content == "old body", "304 must not alter the local body")
assert(last().headers["if-none-match"] == 'W/"old"', "file If-None-Match missing")
assert(last().headers["accept-encoding"] == "identity", "file gzip must not be negotiated")
os.remove(canonical)

print("OK http conditional smoke: 304 GET/file, identity encoding, validators")
