-- SPDX-License-Identifier: MIT
-- Smoke test: Http.get_to_file streaming sink (Lua 5.1) with socket.http stubbed.
-- Covers chunked writes, Content-Length validation, max_bytes and typed statuses.
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
    return { sink = { table = function() return function() return 1 end end } }
end
package.preload["rapidjson"] = function()
    return { decode = function() return nil end }
end

local plans = {}
local calls = 0
package.preload["socket.http"] = function()
    return {
        request = function(req)
            calls = calls + 1
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

local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p '" .. dir .. "'")
local path = dir .. "/body.md.tmp"

local function exists(p)
    local f = io.open(p, "rb")
    if f then f:close() return true end
    return false
end

-- 1) Happy path: two chunks, declared length matches.
plans = { { code = 200, chunks = { "# Title\n", "body\n" }, headers = { ["content-length"] = "13", ["content-type"] = "text/markdown" } } }
local r = Http.get_to_file("https://example.com/a.md", { path = path, max_bytes = 1024 })
assert(r.ok and r.status == 200 and r.bytes == 13, "happy path failed")
assert(exists(path), "file should exist after success")
local f = io.open(path, "rb"); local data = f:read("*a"); f:close()
assert(data == "# Title\nbody\n", "file content mismatch")
os.remove(path)

-- 2) Content-Length mismatch -> incomplete + tmp removed.
plans = { { code = 200, chunks = { "short" }, headers = { ["content-length"] = "99" } } }
r = Http.get_to_file("https://example.com/a.md", { path = path })
assert(not r.ok and r.error_kind == "incomplete", "mismatch should be incomplete")
assert(not exists(path), "tmp must be removed on incomplete")

-- 3) max_bytes enforced during streaming.
plans = { { code = 200, chunks = { "0123456789", "0123456789" }, headers = { ["content-length"] = "20" } } }
r = Http.get_to_file("https://example.com/a.md", { path = path, max_bytes = 5 })
assert(not r.ok and r.error_kind == "too_large", "max_bytes should abort")
assert(not exists(path), "tmp must be removed on too_large")

-- 4) Transport error classification.
plans = { { transport = "timeout" } }
r = Http.get_to_file("https://example.com/a.md", { path = path, retries = 0 })
assert(not r.ok and r.error_kind == "timeout", "transport timeout classification")

-- 5) 404 is typed and never retried.
calls = 0
plans = { { code = 404 } }
r = Http.get_to_file("https://example.com/a.md", { path = path, retries = 3 })
assert(not r.ok and r.error_kind == "http_404" and r.status == 404, "404 classification")
assert(calls == 1, "404 must not be retried")

-- 6) 503 is typed and not retried (only transient timeout/network retry).
calls = 0
plans = { { code = 503 } }
r = Http.get_to_file("https://example.com/a.md", { path = path, retries = 1 })
assert(not r.ok and r.error_kind == "http_503" and calls == 1, "503 must not retry")

-- 7) Transient timeout is retried once and can succeed.
calls = 0
plans = { { transport = "timeout" }, { code = 200, chunks = { "ok" }, headers = { ["content-length"] = "2" } } }
r = Http.get_to_file("https://example.com/a.md", { path = path, retries = 1 })
assert(r.ok and r.bytes == 2 and calls == 2, "timeout should retry once")
os.remove(path)

os.execute("rm -rf '" .. dir .. "'")
print("OK http stream smoke: requests=" .. calls)
