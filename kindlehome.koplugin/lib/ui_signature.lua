-- SPDX-License-Identifier: MIT
-- Deterministic, dependency-free signature of a UI state/model. Used to skip
-- repaints when a refresh produced exactly the pixels already on screen (e.g.
-- a 304 revalidation or an "Updating…" flag that is already cleared).
--
-- Lua 5.1 / LuaJIT only: no table.unpack, no integer division, no bitwise ops.
local UiSignature = {}

local MAX_DEPTH = 24

local function append(out, value, depth)
    if depth > MAX_DEPTH then
        out[#out + 1] = "!"
        return
    end
    local kind = type(value)
    if kind == "nil" then
        out[#out + 1] = "n"
    elseif kind == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif kind == "number" then
        out[#out + 1] = "#" .. string.format("%.6f", value) .. ";"
    elseif kind == "string" then
        out[#out + 1] = "=" .. #value .. ":" .. value .. ";"
    elseif kind == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return tostring(a) < tostring(b)
        end)
        for _, key in ipairs(keys) do
            append(out, key, depth + 1)
            out[#out + 1] = ":"
            append(out, value[key], depth + 1)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        -- Functions/userdata are not part of a renderable model; mark them so
        -- two different opaque values never compare equal by accident.
        out[#out + 1] = "?" .. kind .. tostring(value) .. ";"
    end
end

function UiSignature.of(value)
    local out = {}
    append(out, value, 0)
    return table.concat(out)
end

return UiSignature
