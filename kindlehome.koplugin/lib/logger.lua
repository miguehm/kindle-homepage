-- SPDX-License-Identifier: MIT
local logger = require("logger")

local Logger = {}

local function safe_str(value)
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then
        return tostring(value)
    end
    if value == nil then
        return "nil"
    end
    return t
end

local function emit(level, module_name, event, details)
    local msg = string.format("[KindleHome] module=%s event=%s", safe_str(module_name), safe_str(event))
    if type(details) == "table" then
        local parts = {}
        for k, v in pairs(details) do
            parts[#parts + 1] = tostring(k) .. "=" .. safe_str(v)
        end
        if #parts > 0 then
            table.sort(parts)
            msg = msg .. " " .. table.concat(parts, " ")
        end
    elseif details ~= nil then
        msg = msg .. " detail=" .. safe_str(details)
    end

    if level == "err" and logger.err then
        logger.err(msg)
    elseif level == "warn" and logger.warn then
        logger.warn(msg)
    elseif logger.info then
        logger.info(msg)
    else
        logger.dbg(msg)
    end
end

function Logger.info(module_name, event, details)
    emit("info", module_name, event, details)
end

function Logger.warn(module_name, event, details)
    emit("warn", module_name, event, details)
end

function Logger.err(module_name, event, details)
    emit("err", module_name, event, details)
end

return Logger
