-- SPDX-License-Identifier: MIT
-- Smoke test: persistent UI state (HN page) with atomic writes, clamping,
-- corruption quarantine and graceful degradation without a cache path.
local PLUGIN = (arg and arg[1] or ".") .. "/"
local root = "/tmp/opencode/kindlehome-ui-state-smoke"
os.execute("rm -rf '" .. root .. "'")

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["rapidjson"] = function()
    return {
        encode = function(value)
            return string.format('{"schema_version":%d,"hn_page":%d}',
                tonumber(value.schema_version) or 0, tonumber(value.hn_page) or 0)
        end,
        decode = function(text)
            local schema = tonumber(tostring(text):match('"schema_version"%s*:%s*(%-?%d+)'))
            if not schema then error("invalid json") end
            local page = tonumber(tostring(text):match('"hn_page"%s*:%s*(%-?%d+)'))
            return { schema_version = schema, hn_page = page }
        end,
    }
end

local writes, fail_write = 0, false
local paths = {}
function paths:cache_file(name)
    return root .. "/" .. name
end
function paths:atomic_write(path, content)
    if fail_write then return false, "forced_failure" end
    local dir = path:match("^(.*)/[^/]+$")
    if dir then os.execute("mkdir -p '" .. dir .. "'") end
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local ok = f:write(content)
    f:close()
    if not ok then return false, "write_failed" end
    writes = writes + 1
    return true
end

local function exists(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function list_root()
    local pipe = io.popen("ls -1 '" .. root .. "' 2>/dev/null")
    if not pipe then return "" end
    local text = pipe:read("*a") or ""
    pipe:close()
    return text
end

local UiState = dofile(PLUGIN .. "lib/ui_state.lua")

local first = UiState:new(paths)
assert(first:get_hn_page() == 1, "missing state must default to page 1")
assert(first:set_hn_page(2) == true, "page write failed")
assert(writes == 1 and exists(root .. "/ui_state.json"), "state file not written")
assert(first:set_hn_page(2) == true and writes == 1, "unchanged page must not rewrite")

local second = UiState:new(paths)
assert(second:get_hn_page() == 2, "persisted page not restored")

second:set_hn_page(0)
assert(second:get_hn_page() == 1, "page below one must clamp to page 1")
second:set_hn_page(-4)
assert(second:get_hn_page() == 1, "negative page must clamp to page 1")

local f = assert(io.open(root .. "/ui_state.json", "wb"))
f:write("not json")
f:close()
local corrupt = UiState:new(paths)
assert(corrupt:get_hn_page() == 1, "corrupt state must fall back to page 1")
assert(list_root():find("ui_state.json.corrupt.", 1, true), "corrupt state must be quarantined")

f = assert(io.open(root .. "/ui_state.json", "wb"))
f:write('{"schema_version":99,"hn_page":4}')
f:close()
local incompatible = UiState:new(paths)
assert(incompatible:get_hn_page() == 1, "incompatible state must fall back to page 1")
assert(list_root():find("ui_state.json.corrupt.", 1, true), "incompatible state must be quarantined")

fail_write = true
local failing = UiState:new(paths)
assert(failing:get_hn_page() == 1, "failed write fixture wrong")
assert(failing:set_hn_page(4) == false, "write failure must be reported")
assert(failing:get_hn_page() == 4, "write failure must keep the in-memory page")
fail_write = false
assert(failing:set_hn_page(4) == true, "a failed write must be retried")

local memory_only = UiState:new(nil)
assert(memory_only:get_hn_page() == 1, "no paths must default to page 1")
assert(memory_only:set_hn_page(3) == false, "no paths cannot persist")
assert(memory_only:get_hn_page() == 3, "no paths must keep the in-memory page")

os.execute("rm -rf '" .. root .. "'")
print("OK ui state smoke: default, restore, clamp, quarantine, memory-only")
