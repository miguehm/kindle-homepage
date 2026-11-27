-- SPDX-License-Identifier: MIT
-- Blitbuffer color stub shared by the UI smokes.
--
-- Under LuaJIT the colors are FFI cdata with the same __eq contract as
-- KOReader's ffi/blitbuffer.lua: comparing a color with nil calls
-- `nil:getColorRGB32()` and raises. That is exactly what crashed the
-- dashboard on device (`if self.background ~= nil`), and plain Lua 5.1
-- numbers can never reproduce it. Under Lua 5.1 the colors stay numbers.
local values = { COLOR_WHITE = 255, COLOR_BLACK = 0, COLOR_GRAY_6 = 102, COLOR_GRAY_E = 238 }

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or not rawget(_G, "jit") then
    return values
end

ffi.cdef[[typedef struct { uint8_t a; } kh_smoke_color8;]]
local Color8
Color8 = ffi.metatype("kh_smoke_color8", {
    __index = {
        getColorRGB32 = function(self) return self end,
        invert = function(self) return Color8(255 - self.a) end,
    },
    __eq = function(a, b)
        local c = b:getColorRGB32()
        return a.a == c.a
    end,
})

local colors = {}
for name, value in pairs(values) do colors[name] = Color8(value) end
colors.Color8 = Color8
return colors
