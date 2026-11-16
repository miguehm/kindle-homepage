local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Paths = {}
Paths.__index = Paths

local function join(...)
    local parts = {...}
    local path = table.concat(parts, "/")
    path = path:gsub("//+", "/")
    return path
end

local function mkdir_p(path)
    if not path or path == "" then return false end
    local ok_attr, attr = pcall(lfs.attributes, path)
    if ok_attr and attr and attr.mode == "directory" then
        return true
    end
    local ok = pcall(util.makePath, path)
    if ok then
        local ok2, attr2 = pcall(lfs.attributes, path)
        if ok2 and attr2 and attr2.mode == "directory" then
            return true
        end
    end
    -- fallback: try stepwise
    local prefix = path:sub(1, 1) == "/" and "/" or ""
    local current = prefix
    for part in path:gmatch("[^/]+") do
        current = (current == prefix) and (prefix .. part) or (current .. "/" .. part)
        pcall(lfs.mkdir, current)
    end
    local ok3, attr3 = pcall(lfs.attributes, path)
    return ok3 and attr3 and attr3.mode == "directory"
end

local function slugify(s, fallback)
    s = tostring(s or "")
    s = s:lower()
    s = s:gsub("[%s_]+", "-")
    s = s:gsub("[^%w%-]", "")
    s = s:gsub("%-+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    if s == "" then s = fallback or "item" end
    if #s > 80 then s = s:sub(1, 80):gsub("%-+$", "") end
    return s
end

-- Arithmetic hash only: KOReader on Kindle runs Lua 5.1/LuaJIT, so Lua 5.3
-- bitwise operators (~ & | << >>) must not be used here. The multiplier keeps
-- `h * 65599` below 2^53 so results are identical with doubles (Lua 5.1) and
-- 64-bit integers (Lua 5.3+).
local function short_hash(s)
    s = tostring(s or "")
    local h = 2166136261
    for i = 1, #s do
        h = (h * 65599 + s:byte(i)) % 4294967296
    end
    -- Format as two 16-bit halves so %x never receives a value outside
    -- the 32-bit integer range of Lua 5.1 builds.
    local hi = math.floor(h / 65536)
    local lo = h % 65536
    return string.format("%04x%04x", hi, lo)
end

function Paths:new(config)
    local o = setmetatable({}, self)
    o.config = config
    return o
end

function Paths:data_dir()
    return DataStorage:getDataDir()
end

function Paths:cache_dir()
    return join(self:data_dir(), "cache", "kindlehome")
end

function Paths:cache_file(name)
    return join(self:cache_dir(), name)
end

-- Resolve the user's documents directory (the Kindle library root).
-- DataStorage:getFullDataDir() is the KOReader install/settings dir on Kindle
-- (/mnt/us/koreader), so it must NOT be used for user-visible content.
local function documents_dir()
    local root = nil
    local ok_setting, setting = pcall(function()
        return G_reader_settings and G_reader_settings:readSetting("home_dir")
    end)
    if ok_setting and type(setting) == "string" and setting ~= "" then
        root = setting
    end
    if not root then
        local ok_device, dir = pcall(function()
            local Device = require("device")
            return Device and Device.home_dir
        end)
        if ok_device and type(dir) == "string" and dir ~= "" then
            root = dir
        end
    end
    if not root then
        local ok_storage, dir = pcall(function() return DataStorage:getFullDataDir() end)
        if ok_storage and type(dir) == "string" and dir ~= "" then
            root = dir
        end
    end
    if not root then
        return join(DataStorage:getDataDir(), "documents")
    end
    -- Kindle: Device.home_dir is "/mnt/us" and the library lives in "documents".
    local sub = join(root, "documents")
    local attr = lfs.attributes(sub, "mode")
    if attr == "directory" then
        return sub
    end
    return root
end

function Paths:documents_root()
    local mode = self.config and self.config:get("storage_mode") or "documents"
    if mode == "datadir" then
        return join(self:data_dir(), "news", "kindlehome")
    end
    local subdir = self.config and self.config:get("documents_subdir") or "KindleHome"
    return join(documents_dir(), subdir)
end

function Paths:articles_hn_dir()
    return join(self:documents_root(), "articles", "hn")
end

-- Stable, user-visible name for a downloaded article. The id leads the name so
-- the file is located regardless of rank changes; the slug is cosmetic.
function Paths:article_md_path(item)
    local id = tostring(item and item.id or "")
    id = id:gsub("[^%w_%-]", "")
    if id == "" then id = "unknown" end
    local slug = slugify(item and item.title or "", "article")
    if #slug > 60 then
        slug = slug:sub(1, 60):gsub("%-+$", "")
    end
    return join(self:articles_hn_dir(), id .. "-" .. slug .. ".md")
end

-- Fallback "link card" written when an article cannot be downloaded. Kept
-- separate from the canonical .md so it never counts as a local copy.
function Paths:article_link_path(item)
    local md = self:article_md_path(item)
    if not md then return nil end
    return (md:gsub("%.md$", "-links.md"))
end

-- Derived render opened by KOReader's native reader; KOReader's own file
-- converter uses the same "<file>.html" convention.
function Paths:article_html_path(md_path)
    if type(md_path) ~= "string" or md_path == "" then return nil end
    return md_path .. ".html"
end

function Paths:ensure_dir(path)
    return mkdir_p(path)
end

function Paths:ensure_base_dirs()
    local ok1 = self:ensure_dir(self:cache_dir())
    local ok2 = self:ensure_dir(self:documents_root())
    return ok1 and ok2
end

function Paths:safe_filename(name, ext, disambiguator)
    local base = slugify(name, "item")
    local suffix = ""
    if disambiguator and disambiguator ~= "" then
        suffix = "-" .. short_hash(disambiguator)
    end
    ext = ext and tostring(ext):gsub("^%.", "") or nil
    local filename = base .. suffix
    if ext and ext ~= "" then
        filename = filename .. "." .. ext
    end
    return filename
end

function Paths:atomic_write(path, content)
    if not path or type(content) ~= "string" then
        return false, "invalid_args"
    end
    local dir = path:match("^(.*)/[^/]+$")
    if dir then
        self:ensure_dir(dir)
    end
    local tmp = path .. ".tmp." .. tostring(math.random(100000, 999999))
    local f, err = io.open(tmp, "wb")
    if not f then
        return false, "open_tmp_failed:" .. tostring(err)
    end
    local ok, werr = f:write(content)
    f:close()
    if not ok then
        pcall(os.remove, tmp)
        return false, "write_failed:" .. tostring(werr)
    end
    local renamed, rerr = os.rename(tmp, path)
    if not renamed then
        pcall(os.remove, path)
        renamed, rerr = os.rename(tmp, path)
    end
    if not renamed then
        pcall(os.remove, tmp)
        return false, "rename_failed:" .. tostring(rerr)
    end
    return true
end

return Paths
