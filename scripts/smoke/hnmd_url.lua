-- SPDX-License-Identifier: MIT
-- Smoke test: hnmd URL resolution (origin-absolute content URLs, /v1 prefix).
local PLUGIN = (arg and arg[1] or ".") .. "/"

package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
local next_response = { ok = false }
package.preload["lib/http"] = function()
    return {
        get_json = function() return next_response end,
        get_to_file = function() return { ok = false } end,
    }
end

local Hnmd = dofile(PLUGIN .. "lib/hnmd.lua")

local base = "https://hnmd.example.com/v1"
local cases = {
    { base, "/v1/articles/42.md", "https://hnmd.example.com/v1/articles/42.md" },
    { "https://hnmd.example.com", "/v1/articles/42.md", "https://hnmd.example.com/v1/articles/42.md" },
    { "https://hnmd.example.com/", "articles/42.md", "https://hnmd.example.com/v1/articles/42.md" },
    { base, "https://hnmd.example.com/v1/articles/42.md", "https://hnmd.example.com/v1/articles/42.md" },
}
for _, c in ipairs(cases) do
    local got, err = Hnmd.resolve_content_url(c[1], c[2])
    assert(got == c[3], string.format("resolve(%s, %s) = %s (%s), want %s", c[1], c[2], tostring(got), tostring(err), c[3]))
end

local cross, err = Hnmd.resolve_content_url(base, "https://evil.example.net/v1/articles/42.md")
assert(cross == nil and err == "cross_origin", "cross-origin content_url must be rejected")
local missing, merr = Hnmd.resolve_content_url(base, nil)
assert(missing == nil and merr == "missing_content_url", "missing content_url must be rejected")
local insecure, ierr = Hnmd.resolve_content_url("http://hnmd.example.com/v1", "/v1/articles/42.md")
assert(insecure == nil and ierr == "bad_base_url", "non-https base must be rejected")

local cfg = { get = function(_, k) return ({ hnmd_base_url = base, hnmd_max_items = 50 })[k] end }
local items = {}
for i = 1, 25 do
    table.insert(items, { id = tostring(1000 + i), rank = i, title = "Item " .. i, content_status = "ok", content_url = "/v1/articles/" .. (1000 + i) .. ".md" })
end
next_response = { ok = true, json = { schema_version = 1, items = items } }
local idx = Hnmd.fetch_index(cfg, {})
assert(idx.ok, "index fetch should succeed")
assert(#idx.payload.items == 20, "max_items must clamp to 20")
assert(idx.payload.items[1].id == "1001" and idx.payload.items[1].rank == 1, "rank order preserved")

next_response = { ok = true, json = { schema_version = 99, items = {} } }
local bad = Hnmd.fetch_index(cfg, {})
assert(not bad.ok and bad.error_kind == "parse", "wrong schema_version must be rejected")

next_response = { ok = false, error_kind = "http_401" }
local unauthorized = Hnmd.fetch_index(cfg, {})
assert(not unauthorized.ok and unauthorized.error_kind == "http_401", "401 must propagate")

print("OK hnmd url smoke: " .. #cases .. " resolutions, index checks")
