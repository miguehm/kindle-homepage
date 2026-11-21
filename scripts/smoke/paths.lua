-- Smoke: lib/paths.lua must resolve the custom content folder, keep the
-- legacy modes as fallback, and keep writes canonical/atomic (Lua 5.1).
local PLUGIN = (arg and arg[1] or ".") .. "/"

local root = "/tmp/opencode/kindlehome-paths-smoke"
os.execute("rm -rf '" .. root .. "'")
os.execute("mkdir -p '" .. root .. "/mnt/us/documents'")

local function is_dir(path)
    local ok = os.execute("test -d '" .. path .. "' >/dev/null 2>&1")
    return ok == 0 or ok == true
end

_G.G_reader_settings = { readSetting = function() return nil end }

package.preload["datastorage"] = function()
    return {
        getDataDir = function() return root .. "/data" end,
        getFullDataDir = function() return root .. "/mnt/us/koreader" end,
        getSettingsDir = function() return root .. "/data/settings" end,
    }
end
package.preload["device"] = function()
    return { home_dir = root .. "/mnt/us" }
end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, field)
            if not is_dir(path) then return nil end
            if field == "mode" then return "directory" end
            return { mode = "directory" }
        end,
        mkdir = function(path) os.execute("mkdir -p '" .. path .. "'") end,
    }
end
package.preload["util"] = function()
    return { makePath = function(path) os.execute("mkdir -p '" .. path .. "'") end }
end

local Paths = dofile(PLUGIN .. "lib/paths.lua")
local values = { storage_mode = "documents", documents_subdir = "KindleHome", custom_content_dir = "" }
local config = { get = function(_, key) return values[key] end }
local paths = Paths:new(config)

local documents = root .. "/mnt/us/documents"
local legacy = documents .. "/KindleHome"
assert(paths:documents_root() == legacy, "legacy documents root must be unchanged")
assert(paths:articles_hn_dir() == legacy .. "/articles/hn", "legacy articles dir must be unchanged")

local item = { id = "50517488", title = "Outages reported at Bank of America" }
local md_path = paths:article_md_path(item)
local html_path = paths:article_html_path(md_path)
assert(md_path == legacy .. "/articles/hn/50517488-outages-reported-at-bank-of-america.md", "canonical md path changed")
assert(html_path ~= md_path .. ".html", "derived html must not live next to the canonical md")
assert(html_path:sub(1, #paths:ephemeral_articles_dir() + 1) == paths:ephemeral_articles_dir() .. "/",
    "derived html must live under the plugin cache")
assert(html_path:match("%.html$") ~= nil, "derived html extension changed")
assert(paths:article_html_path(md_path) == html_path, "derived html path must be deterministic")
assert(paths:article_link_path(item) == legacy .. "/articles/hn/50517488-outages-reported-at-bank-of-america-links.md", "link card path changed")
assert(paths:cache_dir() == root .. "/data/cache/kindlehome", "cache must stay in DataDir")

values.storage_mode = "datadir"
assert(paths:documents_root() == root .. "/data/news/kindlehome", "datadir fallback must be preserved")
values.storage_mode = "documents"

local custom = root .. "/custom/Kindle/My Docs"
values.custom_content_dir = custom
assert(paths:documents_root() == custom, "custom absolute folder must win over storage mode")
assert(paths:articles_hn_dir() == custom .. "/articles/hn", "articles dir must follow the custom root")
local article_prefix = custom .. "/articles/hn/"
assert(paths:article_md_path(item):sub(1, #article_prefix) == article_prefix, "article path must follow the custom root")

assert(paths:ensure_base_dirs() == true, "base dirs must be created on demand")
assert(is_dir(paths:cache_dir()) and is_dir(custom), "cache and custom root must exist")

local target = paths:article_md_path(item)
local ok, err = paths:atomic_write(target, "# hello\n")
assert(ok == true, "atomic write failed: " .. tostring(err))
local f = io.open(target, "rb")
assert(f ~= nil, "written article must exist")
assert(f:read("*all") == "# hello\n", "written content mismatch")
f:close()
local leftovers = os.execute("find '" .. custom .. "' -name '*.tmp.*' | grep -q . ")
assert(leftovers ~= 0, "no .tmp leftovers may remain")

values.custom_content_dir = "relative/path"
assert(paths:documents_root() == legacy, "non-absolute custom value must be ignored by the resolver")

os.execute("rm -rf '" .. root .. "'")
print("OK paths smoke: custom folder, legacy fallback, canonical paths and atomic write")
