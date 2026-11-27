-- SPDX-License-Identifier: MIT
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local rapidjson = require("rapidjson")

local Logger = require("lib/logger")

local Cache = {}
Cache.__index = Cache

Cache.SCHEMA_VERSION = 2

local function now_epoch()
    return os.time()
end

local function join(...)
    local parts = {...}
    local path = table.concat(parts, "/")
    return path:gsub("//+", "/")
end

local function ensure_dir(path)
    if not path or path == "" then return false end
    local ok_attr, attr = pcall(lfs.attributes, path)
    if ok_attr and attr and attr.mode == "directory" then return true end
    local current = path:sub(1, 1) == "/" and "/" or ""
    for part in path:gmatch("[^/]+") do
        current = (current == (path:sub(1,1) == "/" and "/" or "")) and (current .. part) or (current .. "/" .. part)
        pcall(lfs.mkdir, current)
    end
    local ok2, attr2 = pcall(lfs.attributes, path)
    return ok2 and attr2 and attr2.mode == "directory"
end

local function atomic_write(path, content)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then ensure_dir(dir) end
    local tmp = path .. ".tmp." .. tostring(math.random(100000, 999999))
    local f = io.open(tmp, "wb")
    if not f then return false, "open_tmp_failed" end
    local ok = f:write(content)
    f:close()
    if not ok then
        pcall(os.remove, tmp)
        return false, "write_failed"
    end
    local renamed = os.rename(tmp, path)
    if not renamed then
        pcall(os.remove, path)
        renamed = os.rename(tmp, path)
    end
    if not renamed then
        pcall(os.remove, tmp)
        return false, "rename_failed"
    end
    return true
end

function Cache:new(paths)
    local o = setmetatable({}, self)
    o.paths = paths
    return o
end

function Cache:dir()
    if self.paths and self.paths.cache_dir then
        return self.paths:cache_dir()
    end
    return join(DataStorage:getDataDir(), "cache", "kindlehome")
end

function Cache:file(name)
    if self.paths and self.paths.cache_file then
        return self.paths:cache_file(name)
    end
    return join(self:dir(), name)
end

function Cache:ensure_dir()
    return ensure_dir(self:dir())
end

local function quarantine(path, reason)
    local ts = tostring(now_epoch())
    local bad = path .. ".corrupt." .. ts
    local ok = os.rename(path, bad)
    if not ok then
        pcall(os.remove, path)
    end
    Logger.warn("cache", "quarantined", { path = path, reason = reason, moved = ok and "yes" or "no" })
end

local function is_valid_envelope(env)
    if type(env) ~= "table" then return false, "not_table" end
    if type(env.schema_version) ~= "number" then return false, "no_schema_version" end
    if env.schema_version ~= Cache.SCHEMA_VERSION then return false, "schema_mismatch" end
    if type(env.fetched_at) ~= "number" then return false, "bad_fetched_at" end
    if type(env.ttl_seconds) ~= "number" then return false, "bad_ttl" end
    if type(env.source) ~= "string" then return false, "bad_source" end
    local st = env.status
    if st ~= "ok" and st ~= "stale" and st ~= "error" then return false, "bad_status" end
    if env.etag ~= nil and type(env.etag) ~= "string" then return false, "bad_etag" end
    return true
end

function Cache:read(name)
    local path = self:file(name)
    local ok_attr, attr = pcall(lfs.attributes, path)
    if not (ok_attr and attr and attr.mode == "file") then
        return nil, "missing"
    end
    local f = io.open(path, "rb")
    if not f then return nil, "open_failed" end
    local content = f:read("*a")
    f:close()
    if type(content) ~= "string" or content == "" then
        quarantine(path, "empty")
        return nil, "empty"
    end
    local ok_decode, decoded = pcall(rapidjson.decode, content)
    if not ok_decode or type(decoded) ~= "table" then
        quarantine(path, "json_invalid")
        return nil, "corrupt"
    end
    local ok_env, reason = is_valid_envelope(decoded)
    if not ok_env then
        quarantine(path, reason or "invalid_envelope")
        return nil, reason or "invalid"
    end
    return decoded, nil
end

function Cache:is_expired(envelope, now)
    if type(envelope) ~= "table" then return true end
    now = now or now_epoch()
    local ttl = tonumber(envelope.ttl_seconds) or 0
    local fetched = tonumber(envelope.fetched_at) or 0
    return (fetched + ttl) <= now
end

function Cache:age_seconds(envelope, now)
    if type(envelope) ~= "table" then return nil end
    now = now or now_epoch()
    local fetched = tonumber(envelope.fetched_at) or 0
    if fetched <= 0 then return nil end
    return math.max(0, now - fetched)
end

function Cache:write(name, opts)
    opts = opts or {}
    self:ensure_dir()
    local envelope = {
        schema_version = Cache.SCHEMA_VERSION,
        fetched_at = opts.fetched_at or now_epoch(),
        ttl_seconds = tonumber(opts.ttl_seconds) or 0,
        source = tostring(opts.source or name),
        status = opts.status or "ok",
        error = opts.error,
        etag = opts.etag,
        payload = opts.payload,
    }
    local ok_enc, encoded = pcall(rapidjson.encode, envelope)
    if not ok_enc or type(encoded) ~= "string" then
        Logger.err("cache", "encode_failed", { name = name })
        return false, "encode_failed"
    end
    local path = self:file(name)
    local ok_write, err = atomic_write(path, encoded)
    if not ok_write then
        Logger.err("cache", "write_failed", { name = name, reason = err })
        return false, err
    end
    Logger.info("cache", "written", { name = name, status = envelope.status })
    return true
end

function Cache:mark_stale(envelope, err_kind, err_detail)
    if type(envelope) ~= "table" then return nil end
    envelope.status = "stale"
    envelope.error = { kind = err_kind or "unknown", detail = err_detail }
    return envelope
end

return Cache
