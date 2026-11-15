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

local function short_hash(s)
    s = tostring(s or "")
    local h = 2166136261
    for i = 1, #s do
        h = h ~ s:byte(i)
        h = (h * 16777619) % 4294967296
    end
    return string.format("%08x", h)
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

function Paths:documents_root()
    local mode = self.config and self.config:get("storage_mode") or "documents"
    if mode == "datadir" then
        return join(self:data_dir(), "news", "kindlehome")
    end
    local subdir = self.config and self.config:get("documents_subdir") or "KindleHome"
    local home = nil
    local ok, dir = pcall(function() return DataStorage:getFullDataDir() end)
    if ok and type(dir) == "string" and dir ~= "" then
        home = dir
    end
    if not home then
        home = join(self:data_dir(), "documents")
    end
    return join(home, subdir)
end

function Paths:articles_hn_dir()
    return join(self:documents_root(), "articles", "hn")
end

function Paths:digest_dir()
    return join(self:documents_root(), "digest")
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
