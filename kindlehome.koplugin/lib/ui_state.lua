-- SPDX-License-Identifier: MIT
-- Small, non-critical UI state persisted across plugin reloads and KOReader
-- restarts. Kept out of the user settings file on purpose: this is derived
-- navigation state, not configuration. Stored as a versioned JSON envelope in
-- the plugin cache dir and written atomically.
local rapidjson = require("rapidjson")

local Logger = require("lib/logger")

local UiState = {}
UiState.__index = UiState

UiState.SCHEMA_VERSION = 1
UiState.FILENAME = "ui_state.json"

local function clamp_page(value)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n)
    if n < 1 then n = 1 end
    return n
end

function UiState:new(paths)
    local o = setmetatable({}, self)
    o.paths = paths
    o.hn_page = nil
    o.persisted = nil
    return o
end

function UiState:_file()
    if not (self.paths and type(self.paths.cache_file) == "function") then
        return nil
    end
    local ok, path = pcall(self.paths.cache_file, self.paths, UiState.FILENAME)
    if ok and type(path) == "string" and path ~= "" then
        return path
    end
    return nil
end

local function quarantine(path)
    local bad = path .. ".corrupt." .. tostring(os.time())
    local ok = pcall(os.rename, path, bad)
    Logger.warn("ui_state", "quarantined", { moved = ok and "yes" or "no" })
end

function UiState:get_hn_page()
    if self.hn_page then return self.hn_page end

    local page = 1
    local path = self:_file()
    self.persisted = path ~= nil
    if path then
        local f = io.open(path, "rb")
        if f then
            local content = f:read("*a")
            f:close()
            local ok_decode, decoded = pcall(rapidjson.decode, content or "")
            local valid = ok_decode and type(decoded) == "table"
                and decoded.schema_version == UiState.SCHEMA_VERSION
            local stored = valid and clamp_page(decoded.hn_page) or nil
            if stored then
                page = stored
            else
                self.persisted = false
                quarantine(path)
            end
        end
    end

    self.hn_page = page
    return page
end

function UiState:set_hn_page(page)
    local n = clamp_page(page) or 1
    if self.hn_page == n and self.persisted then return true end
    self.hn_page = n

    local path = self:_file()
    if not path then
        self.persisted = false
        return false
    end

    local ok_encode, encoded = pcall(rapidjson.encode, {
        schema_version = UiState.SCHEMA_VERSION,
        hn_page = n,
    })
    if not ok_encode or type(encoded) ~= "string" then
        self.persisted = false
        Logger.warn("ui_state", "encode_failed")
        return false
    end

    local ok_write = false
    if type(self.paths.atomic_write) == "function" then
        local ok, written = pcall(self.paths.atomic_write, self.paths, path, encoded)
        ok_write = ok and written == true
    end
    self.persisted = ok_write
    if not ok_write then
        Logger.warn("ui_state", "write_failed")
    end
    return ok_write
end

return UiState
