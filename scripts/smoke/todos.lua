-- SPDX-License-Identifier: MIT
-- Smoke test: TODO'S view (Lua 5.1): model, nav, body, CRUD prompts and doc open.
local PLUGIN = (arg and arg[1] or ".") .. "/"

local SCREEN_W, SCREEN_H, SCROLLBAR = 1200, 1600, 12
local captured_shell, shown, dispatched, notices = nil, 0, {}, {}
local inputs, dialogs, confirms, viewers, tap_icons, datepickers = {}, {}, {}, {}, {}, {}
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
        if o.icon or o.file then tap_icons[#tap_icons + 1] = o end
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
        o.input_fields = {}
        for i, field in ipairs(o.fields or {}) do
            o.input_fields[i] = {
                text = field.text or "",
                setText = function(self, value)
                    self.text = value
                    field.text = value
                end,
            }
        end
        dialogs[#dialogs + 1] = o
        return o
    end
    return M
end
package.preload["ui/widget/datetimewidget"] = function()
    local M = {}
    function M:new(o)
        datepickers[#datepickers + 1] = o
        o.onClose = function() end
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

local function due_date(offset)
    return os.date("!%Y-%m-%d", os.time() + offset * 86400)
end
local today_due, past_due = due_date(0), due_date(-2)

local state_payload = {
    schema_version = 1,
    counts = { open = 2, done = 1, total = 3, due_soon = 1, overdue = 1 },
    tags = {
        { tag = "casa", open = 1, done = 0, total = 1, due_soon = 1, overdue = 0 },
        { tag = "trabajo", open = 0, done = 1, total = 1, due_soon = 0, overdue = 0 },
    },
    truncated = false,
    items = {
        { id = "a1", title = "Comprar leche", tags = { "casa" }, details = "Llamar a la tienda", due_date = today_due, done = false, revision = 1 },
        { id = "b2", title = "Pagar alquiler", tags = {}, details = "", due_date = past_due, done = false, revision = 1 },
        { id = "c3", title = "Revisar correo", tags = { "trabajo" }, details = "", due_date = today_due, done = true, revision = 2 },
    },
}
local applied = 0
package.preload["lib/todos_state"] = function()
    return {
        load = function()
            return { status = "ok", line = "TODO'S — 2 open, 1 done", payload = state_payload,
                     fetched_at = os.time(), stale = false }
        end,
        apply = function(_, _payload) applied = applied + 1 end,
        invalidate = function() end,
    }
end
package.preload["lib/todos"] = function()
    local function success(id, task)
        return { ok = true, status = 200,
                 task = task or { id = id or "new1", title = "Task", tags = {}, done = false, revision = 1 } }
    end
    local function merge(payload, action, task, id)
        payload = payload or {}
        local items = {}
        for _, item in ipairs(payload.items or {}) do table.insert(items, item) end
        if action == "create" and task then table.insert(items, task) end
        if action == "update" and task then
            for index, item in ipairs(items) do
                if item.id == task.id then items[index] = task break end
            end
        end
        if action == "delete" then
            local keep = {}
            for _, item in ipairs(items) do
                if item.id ~= tostring(id) then table.insert(keep, item) end
            end
            items = keep
        end
        local open, done, soon, overdue = 0, 0, 0, 0
        local today = os.date("!%Y-%m-%d", os.time())
        local limit = os.date("!%Y-%m-%d", os.time() + 3 * 86400)
        for _, item in ipairs(items) do
            if item.done then done = done + 1 else open = open + 1 end
            if not item.done and item.due_date then
                if item.due_date < today then overdue = overdue + 1
                elseif item.due_date <= limit then soon = soon + 1 end
            end
        end
        return { items = items, tags = payload.tags or {},
                 counts = { open = open, done = done, total = #items, due_soon = soon, overdue = overdue },
                 truncated = false }
    end
    return {
        valid_due_date = function(value)
            return value == nil or value == "" or type(value) == "string"
                and value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
        end,
        create = function(_, text, tags, details, due)
            table.insert(writes, { kind = "create", text = text, tags = tags, details = details, due = due })
            return success(nil, { id = "new1", title = text, tags = tags or {}, details = details,
                                  due_date = due, done = false, revision = 1 })
        end,
        update = function(_, id, patch)
            table.insert(writes, { kind = "update", id = id, patch = patch })
            local original = {}
            for _, item in ipairs(state_payload.items) do
                if item.id == id then
                    for k, v in pairs(item) do original[k] = v end
                    break
                end
            end
            if patch.text ~= nil then original.title = patch.text end
            if patch.tags ~= nil then original.tags = patch.tags end
            if patch.details ~= nil then original.details = patch.details end
            if patch.done ~= nil then original.done = patch.done end
            if patch.due_date ~= nil then
                original.due_date = patch.due_date ~= "" and patch.due_date or nil
            end
            original.revision = (original.revision or 1) + 1
            return success(id, original)
        end,
        delete_task = function(_, id) table.insert(writes, { kind = "delete", id = id }); return { ok = true, status = 204 } end,
        merge_payload = merge,
        parse_tags = function(input)
            local out = {}
            if input == nil then return out, nil end
            for part in tostring(input):gmatch("[^%s,]+") do
                local tag = part:match("^#+(.+)$") or part
                table.insert(out, tag:lower())
            end
            return out, nil
        end,
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
assert(#model.todos.tags == 4 and model.todos.tags[1].tag == "all"
    and model.todos.tags[1].label == "Sin filtro", "tag chips missing")
assert(model.docs == nil, "the TASK LISTS card must be gone")
local filtered = DashboardModel.build_todos(raw_state, { task_rows = 6, tag_filter = "casa" })
assert(#filtered.todos.items == 1 and filtered.todos.items[1].title == "Comprar leche", "local tag filter failed")
local untagged = DashboardModel.build_todos(raw_state, { task_rows = 6, tag_filter = "__untagged__" })
assert(#untagged.todos.items == 1 and untagged.todos.items[1].title == "Pagar alquiler", "untagged filter failed")
local empty_state = {}
empty_state.todos = { line = "TODO'S unavailable.", payload = { counts = {}, items = {} } }
local empty_model = DashboardModel.build_todos(empty_state, {})
assert(empty_model.todos.empty == "TODO'S unavailable.", "empty model wrong")
local pending_model = DashboardModel.build_todos(raw_state, { task_rows = 6, status_filter = "open" })
assert(pending_model.todos.active_status == "open" and #pending_model.todos.items == 2,
    "pending status filter failed")
local done_model = DashboardModel.build_todos(raw_state, { task_rows = 6, status_filter = "done" })
assert(#done_model.todos.items == 1 and done_model.todos.items[1].title == "Revisar correo",
    "done status filter failed")
assert(#pending_model.todos.status_chips == 5
    and pending_model.todos.status_chips[1].value == "open"
    and pending_model.todos.status_chips[2].value == "done"
    and pending_model.todos.status_chips[3].value == "all"
    and pending_model.todos.status_chips[4].value == "due_soon"
    and pending_model.todos.status_chips[5].value == "overdue", "status chips missing")
local soon_model = DashboardModel.build_todos(raw_state, { task_rows = 6, status_filter = "due_soon" })
assert(#soon_model.todos.items == 1 and soon_model.todos.items[1].id == "a1",
    "due_soon filter failed")
local overdue_model = DashboardModel.build_todos(raw_state, { task_rows = 6, status_filter = "overdue" })
assert(#overdue_model.todos.items == 1 and overdue_model.todos.items[1].id == "b2",
    "overdue filter failed")
local due_label = os.date("!%d-%m-%Y", os.time())
assert(soon_model.todos.items[1].meta:find("Vence: " .. due_label, 1, true) ~= nil,
    "due date must be rendered as DD-MM-YYYY in the row meta")
local both_model = DashboardModel.build_todos(raw_state, {
    task_rows = 6, status_filter = "open", tag_filter = "casa",
})
assert(#both_model.todos.items == 1, "status and tag filters must combine")

local config = {
    get = function(_, key)
        local values = {
            hn_items_per_page = 6, ui_clock_24h = false, show_battery = true,
            show_network = true, refresh_budget_s = 20, ui_font_scale = 1.0,
            todos_include_tags = true, todos_due_soon_days = 3,
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
assert(captured_shell.body.fits == true, "todos body must fit without scrolling")
assert(captured_shell.body.filler == nil or (captured_shell.body.filler.width or 0) <= 0,
    "todos card must absorb the leftover viewport height")
local TodosCard = require("ui/widget/todos_card")
local pager_content = {
    { tag = "header" }, { tag = "divider" }, { tag = "spacer" }, { tag = "pager" },
    getSize = function() return { w = 10, h = 100 } end,
}
local pager_card = { fill_info = { border = 1, padding = 2, has_pager = true }, [1] = pager_content }
TodosCard.apply_fill(pager_card, 120)
assert(#pager_content == 5 and pager_content[4].width == 14 and pager_content[5].tag == "pager"
    and pager_card.fill_info == nil, "pager must stay bottom-anchored inside the filled card")
assert(#captured_shell.body.model.todos.status_chips == 5, "shell must show all five status chips")
assert(type(captured_shell.body.getCropRegion) == "function", "crop region missing")
assert(captured_shell.body.dialog and captured_shell.body.show_parent, "dialog wiring missing")
assert(captured_shell.body.model.nav.active == "todos", "active tab must be todos")
assert(captured_shell.body.model.todos.active_status == "open", "default status must be pending")
assert(#captured_shell.body.model.todos.items == 2, "default view must show only pending tasks")

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

local refresh = nil
for _, widget in ipairs(tap_icons) do
    if type(widget.file) == "string" and widget.file:find("refresh.svg", 1, true) then
        refresh = widget
        break
    end
end
assert(refresh and type(refresh.on_tap) == "function" and refresh.icon == nil,
    "two-arrow refresh asset missing in TASKS header")
refresh:onTapIcon()
assert(dispatched[#dispatched].id == "refresh" and dispatched[#dispatched].ctx.source == "todos",
    "refresh button must dispatch refresh from todos")
assert(icon("book.opened") == nil, "tag chips must not render a book icon")
local eye = nil
for _, widget in ipairs(tap_icons) do
    if type(widget.file) == "string" and widget.file:find("eye.svg", 1, true) then
        eye = widget
        break
    end
end
assert(eye and type(eye.on_tap) == "function", "eye details icon missing")

local status_done = chip("Terminadas: 1")
assert(status_done and type(status_done.on_tap) == "function", "done status chip missing")
status_done:onTapChip()
assert(#captured_shell.body.model.todos.items == 1
    and captured_shell.body.model.todos.active_status == "done", "done filter failed")
chip("Todas: 3"):onTapChip()
assert(#captured_shell.body.model.todos.items == 3, "Todas status chip must show every task")
chip("Pendientes: 2"):onTapChip()
assert(#captured_shell.body.model.todos.items == 2, "Pendientes status chip must reset to open")
chip("Por vencer: 1"):onTapChip()
assert(#captured_shell.body.model.todos.items == 1
    and captured_shell.body.model.todos.active_status == "due_soon", "due soon chip failed")
chip("Vencidas: 1"):onTapChip()
assert(#captured_shell.body.model.todos.items == 1
    and captured_shell.body.model.todos.active_status == "overdue", "overdue chip failed")
chip("Pendientes: 2"):onTapChip()

local casa_chip = chip("#casa: 1")
assert(casa_chip and type(casa_chip.on_tap) == "function", "tag chip missing")
assert(type(casa_chip.on_hold) == "function", "tag chip must support long press")
casa_chip:onTapChip()
assert(#captured_shell.body.model.todos.items == 1, "chip must filter the task list")
assert(captured_shell.body.model.todos.active_tag == "casa", "chip must set the active tag")
chip("Sin filtro: 2"):onTapChip()
assert(#captured_shell.body.model.todos.items == 2, "Sin filtro must clear the tag filter")

local plus = nil
for _, widget in ipairs(tap_icons) do
    if type(widget.file) == "string" and widget.file:find("plus.svg", 1, true) then
        plus = widget
        break
    end
end
assert(plus and type(plus.on_tap) == "function", "solid '+' add icon missing")
assert(plus.width >= 28, "add icon must stay larger than the row icons")
plus:onTapIcon()
local add_dialog = dialogs[#dialogs]
assert(add_dialog and type(add_dialog.getFields) == "function" and #add_dialog.fields == 4,
    "add modal must have four fields")
assert(add_dialog.fields[3].allow_newline == true, "details field must allow newlines")
assert(add_dialog.fields[4].hint == "YYYY-MM-DD", "due date field must document its format")
local due_row = add_dialog.buttons[2]
assert(#due_row == 5, "quick due presets and picker buttons missing")
due_row[1].callback()
assert(add_dialog:getFields()[4] == due_date(0), "Today preset must write a canonical date")
due_row[2].callback()
assert(add_dialog:getFields()[4] == due_date(1), "Tomorrow preset must write a canonical date")
due_row[3].callback()
assert(add_dialog:getFields()[4] == due_date(7), "+1 week preset must write a canonical date")
local pick_button = due_row[4]
assert(pick_button.text == "Pick…", "native date picker button missing")
pick_button.callback()
local picker = datepickers[#datepickers]
assert(picker and picker.year and picker.month and picker.day, "date picker must open with a valid date")
picker.callback({ year = 2027, month = 2, day = 3 })
assert(add_dialog:getFields()[4] == "2027-02-03", "picker must write a canonical due date")
picker.extra_callback(picker)
assert(add_dialog:getFields()[4] == "", "Clear must empty the due date")
add_dialog.fields[1].text = "Comprar pan #casa"
add_dialog.fields[2].text = "casa urgente"
add_dialog.fields[3].text = "En la panadería de la esquina"
add_dialog.fields[4].text = today_due
add_dialog.buttons[1][2].callback()
assert(writes[#writes].kind == "create" and writes[#writes].text == "Comprar pan #casa", "create not dispatched")
assert(writes[#writes].details == "En la panadería de la esquina", "create must send details")
assert(writes[#writes].due == today_due, "create must send the due date")
assert(writes[#writes].tags[1] == "casa" and writes[#writes].tags[2] == "urgente", "create must send tags")
assert(applied == 1, "write must apply locally")
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
assert(eye, "view details icon missing on every row")
rows[1]:onTapRow()
assert(dialogs[#dialogs].fields[1].text == "Comprar leche", "edit modal not prefilled")
assert(dialogs[#dialogs].fields[2].text == "casa", "tags not prefilled in modal")
assert(dialogs[#dialogs].fields[3].text == "Llamar a la tienda", "details not prefilled in modal")
assert(dialogs[#dialogs].fields[4].text == today_due, "due date not prefilled in modal")
dialogs[#dialogs].fields[1].text = "Comprar leche entera"
dialogs[#dialogs].fields[3].text = "Llamar a la tienda grande"
dialogs[#dialogs].buttons[1][2].callback()
assert(writes[#writes].patch.text == "Comprar leche entera", "rename failed")
assert(writes[#writes].patch.details == "Llamar a la tienda grande", "edit must send details")
assert(writes[#writes].patch.tags[1] == "casa", "rename must resend tags")
assert(writes[#writes].patch.due_date == nil, "unchanged due date must not be resent")

eye:onTapIcon()
assert(viewers[#viewers] and viewers[#viewers].text == "Llamar a la tienda grande",
    "eye icon must open the full note in a text viewer")

icon("edit"):onTapIcon()
assert(dialogs[#dialogs].fields[3].text == "Llamar a la tienda grande", "edit icon must prefill details")
assert(dialogs[#dialogs].fields[4].text == today_due, "edit icon must prefill due date")
dialogs[#dialogs].fields[3].text = "nueva nota"
dialogs[#dialogs].buttons[1][2].callback()
assert(writes[#writes].patch.details == "nueva nota", "details patch failed")
assert(writes[#writes].patch.text == nil and writes[#writes].patch.tags == nil,
    "details-only save must not touch text or tags")

icon("edit"):onTapIcon()
dialogs[#dialogs].fields[2].text = ""
dialogs[#dialogs].buttons[1][2].callback()
assert(type(writes[#writes].patch.tags) == "table" and #writes[#writes].patch.tags == 0,
    "emptying the tags field must send an empty tag list")
assert(writes[#writes].patch.text == nil and writes[#writes].patch.details == nil,
    "clearing tags must not touch text or details")

local del = glyph("x")
assert(del, "delete button missing")
del:onTapGlyph()
assert(confirms[#confirms] and type(confirms[#confirms].ok_callback) == "function", "delete confirmation missing")
confirms[#confirms].ok_callback()
assert(writes[#writes].kind == "delete" and writes[#writes].id == "a1", "delete failed")

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

local TodosBody = dofile(PLUGIN .. "ui/todos_body.lua")
local small_body = TodosBody.build(model, config, 600, 800, {
    show_parent = {}, plugin_dir = PLUGIN,
    on_status = function() end, on_tag = function() end, on_tag_doc = function() end,
    on_nav = function() end,
})
assert(small_body and small_body.dimen.h == 800
    and #small_body.model.todos.status_chips == 5,
    "todos body with five status chips must build at small scale")

print("OK todos UI smoke: model=3 tasks nav=3 rows=" .. tostring(#rows) .. " writes=" .. tostring(#writes))
