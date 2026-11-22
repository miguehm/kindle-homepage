-- SPDX-License-Identifier: MIT
-- Smoke test: TODO'S view (Lua 5.1): model, nav, body, CRUD prompts and doc open.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local SCREEN_W, SCREEN_H, SCROLLBAR = 1200, 1600, 12
local captured_shell, shown, dispatched, notices = nil, 0, {}, {}
local inputs, dialogs, confirms, viewers, tap_icons = {}, {}, {}, {}, {}
local writes = {}

local function geom(o)
    o = o or {}
    if o.x == nil then o.x = 0 end
    if o.y == nil then o.y = 0 end
    function o:contains() return true end
    return o
end
local function size_of(widget)
    if type(widget.getSize) == "function" then return widget:getSize() end
    return { w = 0, h = 0 }
end

package.preload["device"] = function()
    return {
        screen = {
            scaleBySize = function(_, n) return math.floor(n * 2) end,
            getWidth = function() return SCREEN_W end,
            getHeight = function() return SCREEN_H end,
        },
        getPowerDevice = function()
            return { getCapacity = function() return 90 end, isCharging = function() return false end }
        end,
    }
end
package.preload["ui/network/manager"] = function()
    return { isConnected = function() return true end }
end
package.preload["gettext"] = function()
    return function(text) return text end
end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_, w) shown = shown + 1; return w end,
        close = function() end,
        setDirty = function() end,
        forceRePaint = function() end,
        scheduleIn = function() end,
    }
end
package.preload["ui/widget/infomessage"] = function()
    local M = {}
    function M:new(o) notices[#notices + 1] = o.text; return o end
    return M
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_WHITE = 255, COLOR_BLACK = 0, COLOR_GRAY_6 = 102, COLOR_GRAY_E = 238 }
end
package.preload["ui/font"] = function()
    return { getFace = function(name, size) return { name = name, size = size } end }
end
package.preload["ui/widget/widget"] = function()
    local Widget = {}
    Widget.__index = Widget
    function Widget:handleEvent() return false end
    function Widget:extend(o)
        o = o or {}; setmetatable(o, self); self.__index = self; return o
    end
    function Widget:new(o) o = self:extend(o); if o.init then o:init() end return o end
    function Widget:getSize() return self.dimen end
    function Widget:paintTo() end
    return Widget
end
package.preload["ui/geometry"] = function()
    local Geom = {}
    Geom.__index = Geom
    function Geom:new(o) return geom(o) end
    return Geom
end
package.preload["ui/gesturerange"] = function()
    return { new = function(_, o) return o end }
end
package.preload["ui/size"] = function()
    return { border = { window = 2 }, line = { thin = 1 } }
end
local TEXT_H = 14
package.preload["ui/widget/textwidget"] = function()
    local M = {}
    function M:new(o)
        o.text = tostring(o.text or "")
        o.getSize = function(self) return { w = math.min(#self.text * 6, 400), h = TEXT_H } end
        return o
    end
    return M
end
package.preload["ui/widget/textboxwidget"] = function()
    local M = {}
    function M:new(o)
        o.text = tostring(o.text or "")
        o.getSize = function(self) return { w = self.width, h = TEXT_H } end
        return o
    end
    return M
end
package.preload["ui/widget/linewidget"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return self.dimen end; return o end
    return M
end
package.preload["ui/widget/verticalspan"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return { w = 0, h = self.width } end; return o end
    return M
end
package.preload["ui/widget/horizontalspan"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return { w = self.width, h = 0 } end; return o end
    return M
end
package.preload["ui/widget/verticalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        function o:getSize()
            local w, h = 0, 0
            for _, child in ipairs(self) do
                local s = size_of(child)
                if s.w > w then w = s.w end
                h = h + s.h
            end
            return { w = w, h = h }
        end
        return o
    end
    return M
end
package.preload["ui/widget/horizontalgroup"] = function()
    local M = {}
    function M:new(o)
        o = o or {}
        function o:getSize()
            local w, h = 0, 0
            for _, child in ipairs(self) do
                local s = size_of(child)
                w = w + s.w
                if s.h > h then h = s.h end
            end
            return { w = w, h = h }
        end
        return o
    end
    return M
end
package.preload["ui/widget/iconwidget"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return { w = self.width or 24, h = self.height or 24 } end; return o end
    return M
end
package.preload["ui/widget/container/centercontainer"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return self.dimen end; return o end
    return M
end
package.preload["ui/widget/container/leftcontainer"] = function()
    local M = {}
    function M:new(o) o.getSize = function(self) return self.dimen end; return o end
    return M
end
package.preload["ui/widget/container/framecontainer"] = function()
    local M = {}
    function M:new(o)
        o.getSize = function(self)
            local s = size_of(self[1])
            local extra = 2 * ((self.bordersize or 0) + (self.padding or 0))
            return { w = s.w + extra, h = s.h + extra }
        end
        return o
    end
    return M
end
package.preload["ui/widget/container/inputcontainer"] = function()
    local M = {}
    function M:getSize() return self.dimen end
    function M:handleEvent() return false end
    function M:paintTo() end
    function M:extend(o)
        o = o or {}; setmetatable(o, self); self.__index = self; return o
    end
    function M:new(o)
        o = self:extend(o)
        inputs[#inputs + 1] = o
        if o.content_group then o.is_row = true end
        if o.icon then tap_icons[#tap_icons + 1] = o end
        if o.init then o:init() end
        return o
    end
    return M
end
package.preload["ui/widget/container/scrollablecontainer"] = function()
    local M = { getScrollbarWidth = function() return SCROLLBAR end }
    function M:new(o)
        o.getSize = function(self) return self.dimen end
        o.getCropRegion = function(self) return self.dimen end
        return o
    end
    return M
end
package.preload["ui/shell"] = function()
    local M = {}
    function M:new(o)
        captured_shell = o
        shown = shown + 1
        local instance = { show = function() end, request_close = function() end, _closing = false }
        if o.header_factory then
            o.header = o.header_factory(SCREEN_W, instance)
        end
        local factory = o.body_factory
        o.body_factory = function(w, h, parent)
            o.body = factory(w, h, parent or instance)
            o.body.dialog = instance
            o.body.show_parent = instance
            return o.body
        end
        if factory then o.body_factory(SCREEN_W, SCREEN_H - 100, instance) end
        return instance
    end
    return M
end
package.preload["ui/widget/dashboard_header"] = function()
    local M = {}
    function M:new(o)
        o.settings_button = { on_tap = o.on_settings }
        o.close_button = { on_tap = o.on_close }
        o.getSize = function() return { w = SCREEN_W, h = 100 } end
        return o
    end
    return M
end
package.preload["ui/widget/multiinputdialog"] = function()
    local M = {}
    function M:new(o)
        o.getFields = function()
            local out = {}
            for i, field in ipairs(o.fields or {}) do out[i] = field.text or "" end
            return out
        end
        dialogs[#dialogs + 1] = o
        return o
    end
    return M
end
package.preload["ui/widget/textviewer"] = function()
    local M = {}
    function M:new(o)
        viewers[#viewers + 1] = o
        return o
    end
    return M
end
package.preload["ui/widget/confirmbox"] = function()
    local M = {}
    function M:new(o) confirms[#confirms + 1] = o; return o end
    return M
end
package.preload["lib/logger"] = function()
    return { info = function() end, warn = function() end, err = function() end }
end
package.preload["lib/refresh"] = function()
    return { new_budget = function() return {} end }
end
package.preload["lib/hnmd"] = function()
    return {
        base_url = function() return "https://example.com/v1" end,
        resolve_content_url = function(_, path) return "https://example.com" .. path end,
    }
end

local state_payload = {
    schema_version = 1,
    counts = { open = 2, done = 1, total = 3 },
    tags = { { tag = "casa", open = 2, done = 0, total = 2 } },
    truncated = false,
    items = {
        { id = "a1", title = "Comprar leche", tags = { "casa" }, details = "Llamar a la tienda", done = false, revision = 1 },
        { id = "b2", title = "Pagar alquiler", tags = {}, details = "", done = false, revision = 1 },
        { id = "c3", title = "Revisar correo", tags = { "trabajo" }, details = "", done = true, revision = 2 },
    },
}
local invalidations = 0
package.preload["lib/todos_state"] = function()
    return {
        load = function()
            return { status = "ok", line = "TODO'S — 2 open, 1 done", payload = state_payload,
                     fetched_at = os.time(), stale = false }
        end,
        invalidate = function() invalidations = invalidations + 1 end,
    }
end
package.preload["lib/todos"] = function()
    local function success(id)
        return { ok = true, status = 200, task = { id = id or "new1", title = "Task", tags = {}, done = false, revision = 1 } }
    end
    return {
        create = function(_, text, _, details)
            table.insert(writes, { kind = "create", text = text, details = details })
            return success()
        end,
        update = function(_, id, patch) table.insert(writes, { kind = "update", id = id, patch = patch }); return success(id) end,
        delete_task = function(_, id) table.insert(writes, { kind = "delete", id = id }); return { ok = true, status = 204 } end,
    }
end
local store_calls = {}
package.preload["lib/article_store"] = function()
    return {
        new = function() return {
            ensure_local = function(_, _, item, o)
                table.insert(store_calls, { id = item.id, force = o and o.force })
                return { ok = true, md_path = "/tmp/todos.md", html_path = "/tmp/todos.html" }
            end,
            is_local = function() return true end,
            render_derived = function() return "/tmp/todos.html" end,
            load_md = function() return "" end,
            remove_ephemeral = function() end,
        } end,
    }
end

for _, name in ipairs({
    "ui/widget/infomessage", "ui/widget/textwidget", "ui/widget/textboxwidget",
    "ui/widget/linewidget", "ui/widget/verticalspan", "ui/widget/horizontalspan",
    "ui/widget/verticalgroup", "ui/widget/horizontalgroup", "ui/widget/iconwidget",
    "ui/widget/container/centercontainer", "ui/widget/container/leftcontainer",
    "ui/widget/container/framecontainer", "ui/widget/container/scrollablecontainer",
    "ui/widget/dashboard_header", "ui/widget/inputdialog", "ui/widget/confirmbox",
}) do
    local original = package.preload[name]
    package.preload[name] = function()
        local module = original()
        if type(module) == "table" and type(module.new) == "function" then
            local original_new = module.new
            module.new = function(...)
                local widget = original_new(...)
                if type(widget) == "table" and type(widget.handleEvent) ~= "function" then
                    widget.handleEvent = function() return false end
                end
                return widget
            end
        end
        return module
    end
end

local DashboardModel = dofile(PLUGIN .. "lib/dashboard_model.lua")
local TodosView = dofile(PLUGIN .. "ui/todos.lua")

local raw_state = {
    time = "14:00", date = "Sunday", battery = "Battery: 90%", network = "Network: connected",
    todos = { status = "ok", payload = state_payload, fetched_at = os.time(), line = "TODO'S" },
    refreshed_at = os.time(),
}
local model = DashboardModel.build_todos(raw_state, { task_rows = 6, todos_page = 1 })
assert(model.nav.active == "todos" and #model.nav.tabs == 3, "todos nav model wrong")
assert(model.todos.items[1].title == "Comprar leche" and model.todos.counts.open == 2, "todos model rows wrong")
assert(model.todos.items[1].details == "Llamar a la tienda", "details lost in model")
assert(#model.todos.tags == 3 and model.todos.tags[1].tag == "all", "tag chips missing")
assert(model.docs == nil, "the TASK LISTS card must be gone")
local filtered = DashboardModel.build_todos(raw_state, { task_rows = 6, tag_filter = "casa" })
assert(#filtered.todos.items == 1 and filtered.todos.items[1].title == "Comprar leche", "local tag filter failed")
local untagged = DashboardModel.build_todos(raw_state, { task_rows = 6, tag_filter = "__untagged__" })
assert(#untagged.todos.items == 1 and untagged.todos.items[1].title == "Pagar alquiler", "untagged filter failed")
local empty_state = {}
empty_state.todos = { line = "TODO'S unavailable.", payload = { counts = {}, items = {} } }
local empty_model = DashboardModel.build_todos(empty_state, {})
assert(empty_model.todos.empty == "TODO'S unavailable.", "empty model wrong")

local config = {
    get = function(_, key)
        local values = {
            hn_items_per_page = 6, ui_clock_24h = false, show_battery = true,
            show_network = true, refresh_budget_s = 20, ui_font_scale = 1.0,
            todos_include_tags = true,
        }
        return values[key]
    end,
}
local actions = {
    dispatch = function(_, id, ctx) table.insert(dispatched, { id = id, ctx = ctx }); return true end,
}
local article_doc
local article_view = {
    will_open_in_reader = function() return false end,
    show = function(_, doc) article_doc = doc end,
}
local view = TodosView:new{
    config = config, paths = { article_md_path = function() return "/tmp/todos.md" end },
    actions = actions, article_view = article_view, plugin_dir = PLUGIN,
}

view:show({ allow_network = false })
assert(shown == 1 and captured_shell and captured_shell.title == "TODO'S", "todos shell missing")
assert(captured_shell.body.fits ~= nil, "todos body fit flag missing")
assert(type(captured_shell.body.getCropRegion) == "function", "crop region missing")
assert(captured_shell.body.dialog and captured_shell.body.show_parent, "dialog wiring missing")
assert(captured_shell.body.model.nav.active == "todos", "active tab must be todos")

local nav_cells = {}
for _, input in ipairs(inputs) do
    if input.name then nav_cells[#nav_cells + 1] = input end
end
assert(#nav_cells == 3, "expected 3 tabs, got " .. tostring(#nav_cells))
for _, cell in ipairs(nav_cells) do
    assert(type(cell.on_tap) == "function", "nav wiring wrong")
end
nav_cells[1]:onTapNavCell()
assert(dispatched[#dispatched].id == "nav" and dispatched[#dispatched].ctx.tab == "dashboard", "nav to dashboard failed")
assert(dispatched[#dispatched].ctx.from == "todos", "nav origin missing")
nav_cells[3]:onTapNavCell()
assert(dispatched[#dispatched].ctx.tab == "store", "store must stay a placeholder")

local function glyph(text)
    for _, input in ipairs(inputs) do
        if input.text == text then return input end
    end
    return nil
end

local function icon(name)
    for _, widget in ipairs(tap_icons) do
        if widget.icon == name then return widget end
    end
    return nil
end

local function chip(text)
    for _, input in ipairs(inputs) do
        if input.text == text then return input end
    end
    return nil
end

local refresh = icon("cre.render.reload")
assert(refresh and type(refresh.on_tap) == "function", "refresh button missing in TASKS header")
refresh:onTapIcon()
assert(dispatched[#dispatched].id == "refresh" and dispatched[#dispatched].ctx.source == "todos",
    "refresh button must dispatch refresh from todos")
assert(icon("book.opened"), "per-tag Markdown icon missing")
local casa_chip = chip("#casa 2")
assert(casa_chip and type(casa_chip.on_tap) == "function", "tag chip missing")
casa_chip:onTapChip()
assert(#captured_shell.body.model.todos.items == 1, "chip must filter the task list")
assert(captured_shell.body.model.todos.active_tag == "casa", "chip must set the active tag")
chip("Todas 3"):onTapChip()
assert(#captured_shell.body.model.todos.items == 3, "Todas must clear the filter")

local plus = glyph("+")
assert(plus and type(plus.on_tap) == "function", "add button missing")
plus:onTapGlyph()
local add_dialog = dialogs[#dialogs]
assert(add_dialog and type(add_dialog.getFields) == "function" and #add_dialog.fields == 2, "add modal must have two fields")
assert(add_dialog.fields[2].allow_newline == true, "details field must allow newlines")
add_dialog.fields[1].text = "Comprar pan #casa"
add_dialog.fields[2].text = "En la panadería de la esquina"
add_dialog.buttons[1][2].callback()
assert(writes[#writes].kind == "create" and writes[#writes].text == "Comprar pan #casa", "create not dispatched")
assert(writes[#writes].details == "En la panadería de la esquina", "create must send details")
assert(invalidations == 1, "write must invalidate caches")
assert(notices[#notices] == "Task added.", "create notice missing")

local checkbox = glyph("[ ]")
assert(checkbox, "open-task checkbox missing")
checkbox:onTapGlyph()
assert(writes[#writes].kind == "update" and writes[#writes].patch.done == true, "toggle failed")
local done_checkbox = glyph("[x]")
assert(done_checkbox, "done-task checkbox missing")
done_checkbox:onTapGlyph()
assert(writes[#writes].patch.done == false, "untoggle failed")

local rows = {}
for _, input in ipairs(inputs) do
    if input.is_row then rows[#rows + 1] = input end
end
assert(#rows >= 3, "task rows missing")
local edit_icons = {}
for _, widget in ipairs(tap_icons) do
    if widget.icon == "edit" then edit_icons[#edit_icons + 1] = widget end
end
assert(#edit_icons >= #rows, "edit details must be available on every row, even without details")
assert(icon("notice-info"), "view details icon missing on every row")
rows[1]:onTapRow()
assert(dialogs[#dialogs].fields[1].text == "Comprar leche", "edit modal not prefilled")
assert(dialogs[#dialogs].fields[2].text == "Llamar a la tienda", "details not prefilled in modal")
dialogs[#dialogs].fields[1].text = "Comprar leche entera"
dialogs[#dialogs].fields[2].text = "Llamar a la tienda grande"
dialogs[#dialogs].buttons[1][2].callback()
assert(writes[#writes].patch.text == "Comprar leche entera", "rename failed")
assert(writes[#writes].patch.details == "Llamar a la tienda grande", "edit must send details")

local del = glyph("x")
assert(del, "delete button missing")
del:onTapGlyph()
assert(confirms[#confirms] and type(confirms[#confirms].ok_callback) == "function", "delete confirmation missing")
confirms[#confirms].ok_callback()
assert(writes[#writes].kind == "delete" and writes[#writes].id == "a1", "delete failed")

local info = icon("notice-info")
assert(info and type(info.on_tap) == "function", "view details icon missing")
info:onTapIcon()
assert(viewers[#viewers] and viewers[#viewers].text == "Llamar a la tienda",
    "view details icon must open the full note in a text viewer")
icon("edit"):onTapIcon()
assert(dialogs[#dialogs].fields[2].text == "Llamar a la tienda", "edit icon must prefill details")
dialogs[#dialogs].fields[2].text = "nueva nota"
dialogs[#dialogs].buttons[1][2].callback()
assert(writes[#writes].patch.details == "nueva nota", "details patch failed")

view:handle_link("kh:todos:tagdoc:casa")
assert(store_calls[#store_calls].id == "todos-tag-casa" and store_calls[#store_calls].force == true,
    "per-tag markdown must be re-downloaded on open")
assert(article_doc and article_doc.kind == "todo" and article_doc.origin == "todos", "todo doc missing")
assert(type(article_doc.on_close) == "function", "todo doc close hook missing")

view:handle_link("kh:settings")
assert(dispatched[#dispatched].id == "settings", "settings link failed")
view:handle_link("kh:refresh")
assert(dispatched[#dispatched].id == "refresh" and dispatched[#dispatched].ctx.source == "todos", "refresh source wrong")

local function has_handle_event(node, seen)
    if type(node) ~= "table" or seen[node] then return true end
    seen[node] = true
    if type(node.getSize) == "function" then
        assert(type(node.handleEvent) == "function", "widget without handleEvent in tree")
    end
    for _, child in pairs(node) do has_handle_event(child, seen) end
    return true
end
has_handle_event(captured_shell.body, {})

print("OK todos UI smoke: model=3 tasks nav=3 rows=" .. tostring(#rows) .. " writes=" .. tostring(#writes))
