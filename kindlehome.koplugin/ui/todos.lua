-- SPDX-License-Identifier: MIT
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextViewer = require("ui/widget/textviewer")
local _ = require("gettext")

local ArticleStore = require("lib/article_store")
local DashboardModel = require("lib/dashboard_model")
local Hnmd = require("lib/hnmd")
local Logger = require("lib/logger")
local Messages = require("ui/messages")
local Refresh = require("lib/refresh")
local Todos = require("lib/todos")
local TodosBody = require("ui/todos_body")
local TodosState = require("lib/todos_state")
local Shell = require("ui/shell")
local DashboardHeader = require("ui/widget/dashboard_header")

local TodosView = {}

local MAX_DETAILS_BYTES = 1000

local function details_error(details)
    if #tostring(details or "") > MAX_DETAILS_BYTES then
        return Messages.for_kind("todos_details_invalid")
    end
    return nil
end

local function due_error(due)
    if not Todos.valid_due_date(due) then
        return Messages.for_kind("todos_invalid_due_date")
    end
    return nil
end

-- Presets and the native picker both emit the canonical UTC YYYY-MM-DD form
-- that lib/todos.lua validates and the backend expects.
local function due_from_offset(days)
    return os.date("!%Y-%m-%d", os.time() + days * 86400)
end

local function due_parts(value)
    local y, m, d = tostring(value or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y and m and d and y >= 1 and m >= 1 and m <= 12 and d >= 1 and d <= 31 then
        return y, m, d
    end
    local now = os.date("!*t")
    return now.year, now.month, now.day
end

function TodosView:new(opts)
    opts = opts or {}
    local ok_dt, DateTimeWidget = pcall(function() return require("ui/widget/datetimewidget") end)
    if not ok_dt then
        Logger.warn("todos_view", "datetime_widget_unavailable", { err = tostring(DateTimeWidget) })
        DateTimeWidget = nil
    end
    local o = {
        config = opts.config,
        paths = opts.paths,
        actions = opts.actions,
        article_view = opts.article_view,
        plugin_dir = opts.plugin_dir,
        widget = nil,
        todos_page = 1,
        article_store = opts.paths and ArticleStore:new(opts.paths) or nil,
        task_index = {},
        tag_index = {},
        tag_filter = nil,
        status_filter = "open",
        last_state = nil,
        refreshing = false,
        datetime_widget = DateTimeWidget,
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

local function get_clock_state()
    local ok_time, t = pcall(os.date, "*t")
    local ok_str, date_str = pcall(os.date, "%A, %B %d, %Y")
    local ok_hm, time_str = pcall(os.date, "%H:%M")
    if not (ok_time and t and ok_str and ok_hm) then
        return "Date unavailable", "Time unavailable"
    end
    return date_str, time_str
end

local function get_battery_state(config)
    if config and not config:get("show_battery") then return "Battery: hidden" end
    local ok, powerd = pcall(function() return Device:getPowerDevice() end)
    if not ok or not powerd then return "Battery: unavailable" end
    local parts = {}
    local ok_cap, cap = pcall(function() return powerd:getCapacity() end)
    if ok_cap and cap ~= nil then table.insert(parts, tostring(cap) .. "%") end
    local charging = nil
    if type(powerd.isCharging) == "function" then
        local ok_c, c = pcall(function() return powerd:isCharging() end)
        if ok_c then charging = c end
    elseif type(powerd.is_charging) == "function" then
        local ok_c, c = pcall(function() return powerd:is_charging() end)
        if ok_c then charging = c end
    end
    if charging == true then
        table.insert(parts, "charging")
    elseif charging == false and #parts > 0 then
        table.insert(parts, "not charging")
    end
    if #parts == 0 then return "Battery: unavailable" end
    return "Battery: " .. table.concat(parts, ", ")
end

local function get_network_state(config)
    if config and not config:get("show_network") then return "Network: hidden" end
    local connected = false
    local ok_conn, conn = pcall(function() return NetworkMgr:isConnected() end)
    if ok_conn then connected = conn and true or false end
    if not connected then return "Network: disconnected" end
    return "Network: connected"
end

function TodosView:is_online()
    local ok, conn = pcall(function() return NetworkMgr:isConnected() end)
    return ok and conn and true or false
end

function TodosView:_index_payload(payload)
    self.task_index = {}
    self.tag_index = {}
    payload = payload or {}
    for _, task in ipairs(payload.items or {}) do
        if task.id then self.task_index[tostring(task.id)] = task end
    end
    for _, entry in ipairs(payload.tags or {}) do
        if entry.tag then self.tag_index[tostring(entry.tag)] = entry end
    end
end

function TodosView:show_notice(text)
    if not text or text == "" then return end
    UIManager:show(InfoMessage:new{ text = text, timeout = 4 })
end

function TodosView:load_sources(opts)
    local budget = opts.budget or Refresh.new_budget(self.config and self.config:get("refresh_budget_s") or 20)
    local allow_network = opts.allow_network
    if allow_network == nil then allow_network = self:is_online() end
    local ok_all, todos = pcall(TodosState.load, self.config, self.paths, {
        allow_network = allow_network, budget = budget,
    })
    if not ok_all then
        Logger.err("todos_view", "load_exception", { source = "todos" })
        todos = { status = "error", line = "TODO'S unavailable.", error_kind = "exception" }
    end
    return todos
end

function TodosView:build_state(opts)
    opts = opts or {}
    local date_str, time_str = get_clock_state()
    local todos = self:load_sources(opts)
    local state = {
        date = date_str,
        time = time_str,
        battery = get_battery_state(self.config),
        network = get_network_state(self.config),
        todos = todos,
        refreshed_at = todos and todos.fetched_at or nil,
        refreshing = opts.refreshing == true,
        show_battery = (not self.config) or self.config:get("show_battery"),
        show_network = (not self.config) or self.config:get("show_network"),
    }
    self.last_state = state
    local payload = todos and todos.payload or {}
    self:_index_payload(payload)
    Logger.info("todos_view", "state_built", {
        todos = todos and todos.status or "nil",
        tasks = #(payload.items or {}),
        tags = #(payload.tags or {}),
    })
    return state
end

local function tags_to_input(tags)
    local parts = {}
    for _, tag in ipairs(tags or {}) do table.insert(parts, tostring(tag)) end
    return table.concat(parts, " ")
end

function TodosView:_pick_due_date(dialog, set_due)
    local DateTimeWidget = self.datetime_widget
    if not DateTimeWidget then return end
    local fields = type(dialog.getFields) == "function" and dialog:getFields() or {}
    local year, month, day = due_parts(fields[4])
    local picker
    local function restore_keyboard()
        if type(dialog.onShowKeyboard) == "function" then dialog:onShowKeyboard() end
    end
    picker = DateTimeWidget:new{
        year = year,
        month = month,
        day = day,
        title_text = _("Set due date"),
        ok_text = _("Set"),
        extra_text = _("Clear"),
        extra_callback = function()
            set_due("")
            if picker and type(picker.onClose) == "function" then picker:onClose() end
            restore_keyboard()
        end,
        callback = function(value)
            set_due(string.format("%04d-%02d-%02d", value.year, value.month, value.day))
            restore_keyboard()
        end,
    }
    UIManager:show(picker)
end

function TodosView:prompt_task(title, initial_text, initial_tags, initial_details, initial_due, on_save)
    local dialog
    local function set_due(value)
        value = value or ""
        if dialog.input_fields and dialog.input_fields[4]
                and type(dialog.input_fields[4].setText) == "function" then
            dialog.input_fields[4]:setText(value)
        end
        dialog.fields[4].text = value
    end
    local due_row = {
        { text = _("Today"), callback = function() set_due(due_from_offset(0)) end },
        { text = _("Tomorrow"), callback = function() set_due(due_from_offset(1)) end },
        { text = _("+1 week"), callback = function() set_due(due_from_offset(7)) end },
    }
    if self.datetime_widget then
        table.insert(due_row, { text = _("Pick…"), callback = function()
            self:_pick_due_date(dialog, set_due)
        end })
    end
    table.insert(due_row, { text = _("Clear"), callback = function() set_due("") end })
    local buttons = {
        {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local fields = dialog:getFields() or {}
                    local text = tostring(fields[1] or ""):match("^%s*(.-)%s*$") or ""
                    local tags_input = tostring(fields[2] or "")
                    local details = tostring(fields[3] or "")
                    local due_input = tostring(fields[4] or ""):match("^%s*(.-)%s*$") or ""
                    local tags, tag_err = Todos.parse_tags(tags_input)
                    if tag_err then
                        self:show_notice(Messages.for_kind("todos_invalid_tags"))
                        return
                    end
                    local ok, msg = on_save(text, tags, details, due_input)
                    if ok == false then
                        self:show_notice(msg)
                        return
                    end
                    UIManager:close(dialog)
                    if msg then self:show_notice(msg) end
                end,
            },
        },
    }
    table.insert(buttons, due_row)
    dialog = MultiInputDialog:new{
        title = title,
        fields = {
            {
                description = _("Task"),
                text = initial_text or "",
                hint = _("Task text"),
            },
            {
                description = _("Tags (optional)"),
                text = initial_tags or "",
                hint = _("Space or comma separated; #optional"),
            },
            {
                description = _("Details (optional)"),
                text = initial_details or "",
                hint = _("Notes"),
                allow_newline = true,
            },
            {
                description = _("Due date (optional)"),
                text = initial_due or "",
                hint = _("YYYY-MM-DD"),
            },
        },
        buttons = buttons,
    }
    UIManager:show(dialog)
    if type(dialog.onShowKeyboard) == "function" then dialog:onShowKeyboard() end
    return dialog
end

-- Apply the server's response to the payload the user is looking at. This
-- makes writes deterministic and independent of the network: no extra GET is
-- needed, and a failed next refresh cannot roll back a successful save.
function TodosView:_apply_local(mutation, task)
    local state = self.last_state
    if not state or not state.todos then return end
    local merged = Todos.merge_payload(state.todos.payload, mutation.kind, task, mutation.id, {
        now = os.time(),
        due_days = self.config and self.config:get("todos_due_soon_days") or nil,
        use_local = (self.config and self.config:get("todos_timezone") or "") ~= "",
    })
    state.todos.payload = merged
    state.todos.line = string.format("TODO'S — %d open, %d done",
        merged.counts.open or 0, merged.counts.done or 0)
    state.todos.status = "ok"
    state.todos.stale = false
    state.todos.error_kind = nil
    state.todos.message = nil
    state.todos.fetched_at = os.time()
    state.refreshed_at = os.time()
    self:_index_payload(merged)
    if self.paths then pcall(TodosState.apply, self.paths, merged) end
end

function TodosView:apply_write(run, success_key, mutation)
    local ok, res = pcall(run)
    if not ok then
        Logger.err("todos_view", "write_exception")
        self:show_notice(Messages.for_kind("todos_write_failed"))
        return false
    end
    if not res.ok then
        self:show_notice(Messages.todos_write(res))
        if res.error_kind == "revision_conflict" or res.error_kind == "precondition_required"
                or res.error_kind == "missing_revision" then
            -- Never silently overwrite a change made on another device: drop
            -- the stale local copy, reload from the server and ask the user to
            -- repeat the action with the fresh revision.
            Logger.warn("todos_view", "write_conflict", {
                kind = res.error_kind, status = res.status, current_revision = res.current_revision,
            })
            if self.paths then pcall(TodosState.invalidate, self.paths) end
            self:refresh({ allow_network = true })
        end
        return false
    end
    if mutation then self:_apply_local(mutation, res.task) end
    self:show_notice(Messages.for_kind(success_key))
    self:show({ state = self.last_state, allow_network = false })
    return true
end

function TodosView:add_task()
    self:prompt_task(_("New task"), "", "", "", "", function(text, tags, details, due)
        if text == "" then return false, Messages.for_kind("todos_invalid_text") end
        local err = details_error(details)
        if err then return false, err end
        local due_err = due_error(due)
        if due_err then return false, due_err end
        return self:apply_write(function()
            return Todos.create(self.config, text, tags, details, due)
        end, "todos_created", { kind = "create" }), nil
    end)
end

function TodosView:get_task(id)
    return self.task_index and self.task_index[tostring(id)] or nil
end

function TodosView:toggle_task(id)
    local task = self:get_task(id)
    if not task then
        self:show_notice(Messages.for_kind("not_found"))
        return
    end
    local done = task.done and true or false
    self:apply_write(function()
        return Todos.update(self.config, id, { done = not done }, { revision = task.revision })
    end, "todos_updated", { kind = "update" })
end

function TodosView:rename_task(id)
    local task = self:get_task(id)
    if not task then
        self:show_notice(Messages.for_kind("not_found"))
        return
    end
    self:prompt_task(_("Edit task"), task.title or "", tags_to_input(task.tags),
        task.details or "", task.due_date or "", function(text, tags, details, due)
        if text == "" then return false, Messages.for_kind("todos_invalid_text") end
        local err = details_error(details)
        if err then return false, err end
        err = due_error(due)
        if err then return false, err end
        local patch = {}
        if text ~= tostring(task.title or "") then patch.text = text end
        local existing = {}
        for _, tag in ipairs(task.tags or {}) do table.insert(existing, tostring(tag)) end
        local same_tags = #existing == #tags
        if same_tags then
            local in_existing, in_new = {}, {}
            for _, tag in ipairs(existing) do in_existing[tag] = true end
            for _, tag in ipairs(tags) do in_new[tag] = true end
            for tag in pairs(in_existing) do
                if not in_new[tag] then same_tags = false break end
            end
            if same_tags then
                for tag in pairs(in_new) do
                    if not in_existing[tag] then same_tags = false break end
                end
            end
        end
        -- Always resend tags alongside text: the backend must never reparse a
        -- title without an explicit tag list and drop the task's tags.
        if patch.text ~= nil or not same_tags then patch.tags = tags end
        if details ~= tostring(task.details or "") then patch.details = details end
        if due ~= tostring(task.due_date or "") then patch.due_date = due end
        if next(patch) == nil then
            return true, Messages.for_kind("todos_no_changes")
        end
        return self:apply_write(function()
            return Todos.update(self.config, id, patch, { revision = task.revision })
        end, "todos_updated", { kind = "update" }), nil
    end)
end

function TodosView:delete_task(id)
    local task = self:get_task(id)
    if not task then
        self:show_notice(Messages.for_kind("not_found"))
        return
    end
    local confirm
    confirm = ConfirmBox:new{
        text = _("Delete this task?"),
        ok_text = _("Delete"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            UIManager:close(confirm)
            self:apply_write(function()
                return Todos.delete_task(self.config, id, { revision = task.revision })
            end, "todos_deleted", { kind = "delete", id = id })
        end,
    }
    UIManager:show(confirm)
end

function TodosView:_article_meta(item)
    return {
        id = tostring(item.id or ""),
        title = tostring(item.title or "Todos"),
        source = "hnmd/todos",
        date = item.updated_at or os.date("%Y-%m-%d"),
        status = tostring(item.content_status or "ok"),
        hn_url = item.hn_url,
    }
end

function TodosView:_cleanup_html(html_path)
    if html_path and self.article_store and type(self.article_store.remove_ephemeral) == "function" then
        self.article_store:remove_ephemeral(html_path)
    end
end

function TodosView:_open_document(doc)
    if self.article_view and type(self.article_view.will_open_in_reader) == "function"
        and self.article_view:will_open_in_reader(doc) then
        self.widget = nil
    else
        self:_teardown()
    end
    if self.article_view then
        self.article_view:show(doc)
    else
        Logger.warn("todos_view", "no_article_view")
    end
end

function TodosView:_open_article(meta, item, md_path, html_path, status)
    local doc = {
        kind = "todo",
        origin = "todos",
        id = meta.id,
        title = meta.title,
        meta = meta,
        status = status or "ok",
        md_path = md_path,
        html_path = html_path,
        on_back = function() self:show({ allow_network = false }) end,
        on_close = function() self:show({ allow_network = false }) end,
        on_fallback = function() self:_teardown() end,
        on_cleanup = function() self:_cleanup_html(html_path) end,
    }
    if not doc.html_path then
        doc.md = self.article_store and self.article_store:load_md(md_path) or ""
    end
    self:_open_document(doc)
end

function TodosView:open_tag(tag)
    tag = tostring(tag or "")
    local entry = self.tag_index and self.tag_index[tag] or nil
    if not entry then
        self:show_notice(Messages.for_kind("not_found"))
        return
    end
    if not (self.paths and self.article_store) then
        self:show_notice(Messages.for_kind("content_unavailable"))
        return
    end
    local base = Hnmd.base_url(self.config)
    if not base then
        self:show_notice(Messages.for_kind("bad_base_url", "Invalid base URL."))
        return
    end
    local status = self.status_filter or "open"
    if status ~= "open" and status ~= "done" and status ~= "due_soon" and status ~= "overdue" then
        status = "all"
    end
    local count_key, noun = "total", "tareas"
    if status == "open" then count_key, noun = "open", "abiertas" end
    if status == "done" then count_key, noun = "done", "terminadas" end
    if status == "due_soon" then count_key, noun = "due_soon", "por vencer" end
    if status == "overdue" then count_key, noun = "overdue", "vencidas" end
    local content_url = "/v1/todos/tags/" .. tag .. ".md?status=" .. status
    if status == "due_soon" and self.config then
        content_url = content_url .. "&due_days=" .. tostring(self.config:get("todos_due_soon_days"))
    end
    local tz = self.config and self.config:get("todos_timezone") or ""
    if type(tz) == "string" and tz ~= "" then
        content_url = content_url .. "&tz=" .. tostring(tz):gsub("([^%w%-_~%.])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end
    local item = {
        id = "todos-tag-" .. tag,
        title = "#" .. tag .. " (" .. tostring(tonumber(entry[count_key]) or 0) .. " " .. noun .. ")",
        hn_url = Hnmd.resolve_content_url(base, content_url) or (base .. content_url),
        content_status = "ok",
        content_url = content_url,
        updated_at = self.last_state and self.last_state.refreshed_at and
            os.date("%Y-%m-%dT%H:%M:%SZ", self.last_state.refreshed_at) or nil,
    }
    local meta = self:_article_meta(item)
    local md_path = self.paths:article_md_path(item)
    local notice = InfoMessage:new{ text = Messages.for_kind("downloading", "Downloading…") }
    UIManager:show(notice)
    pcall(function() UIManager:forceRePaint() end)
    local res = self.article_store:ensure_local(self.config, item, { force = true })
    pcall(function() UIManager:close(notice) end)
    if not res.ok then
        if res.md_path and self.article_store:is_local(res.md_path) then
            local stale_html = self.article_store:render_derived(res.md_path, item, false)
            self:_open_article(meta, item, res.md_path, stale_html, "stale")
        else
            self:show_notice(Messages.reading(res.error_kind))
        end
        return
    end
    self:_open_article(meta, item, res.md_path, res.html_path, "ok")
end

function TodosView:set_tag_filter(tag)
    tag = tostring(tag or "")
    if tag == "all" then tag = "" end
    self.tag_filter = tag ~= "" and tag or nil
    self.todos_page = 1
    if self.last_state then
        self:show({ state = self.last_state, allow_network = false })
    end
end

function TodosView:set_status_filter(status)
    status = tostring(status or "open")
    if status ~= "open" and status ~= "done" and status ~= "all"
            and status ~= "due_soon" and status ~= "overdue" then status = "open" end
    self.status_filter = status
    self.todos_page = 1
    if self.last_state then
        self:show({ state = self.last_state, allow_network = false })
    end
end

function TodosView:show_details(id)
    local task = self:get_task(id)
    if not task then
        self:show_notice(Messages.for_kind("not_found"))
        return
    end
    local details = tostring(task.details or "")
    if details == "" then
        self:show_notice(Messages.for_kind("todos_no_details", "No details for this task."))
        return
    end
    UIManager:show(TextViewer:new{
        title = task.title or _("Task details"),
        text = details,
    })
end

function TodosView:edit_details(id)
    self:rename_task(id)
end

function TodosView:handle_link(uri)
    uri = tostring(uri or "")
    if uri == "kh:refresh" then
        if self.actions then
            self.actions:dispatch("refresh", { source = "todos", todos = self, user_initiated = true })
        else
            self:refresh({ allow_network = false, reset_page = true })
        end
        return true
    elseif uri == "kh:close" then
        if self.actions then
            self.actions:dispatch("close", { source = "todos", todos = self })
        else
            self:close()
        end
        return true
    elseif uri == "kh:settings" then
        if self.actions then
            self.actions:dispatch("settings", { source = "todos", todos = self })
        end
        return true
    end

    local tab = uri:match("^kh:nav:(.+)$")
    if tab then
        if tab == "todos" then return true end
        if self.actions then
            self.actions:dispatch("nav", { from = "todos", tab = tab })
        else
            self:show_notice(Messages.for_kind("coming_soon", "Coming soon."))
        end
        return true
    end

    local cmd, arg = uri:match("^kh:todos:([%w_%-]+):?([%w_%-]*)$")
    if cmd == "add" then self:add_task(); return true end
    if cmd == "toggle" and arg ~= "" then self:toggle_task(arg); return true end
    if cmd == "rename" and arg ~= "" then self:rename_task(arg); return true end
    if cmd == "delete" and arg ~= "" then self:delete_task(arg); return true end
    if cmd == "details" and arg ~= "" then self:edit_details(arg); return true end
    if cmd == "tag" and arg ~= "" then self:set_tag_filter(arg); return true end
    if cmd == "status" and arg ~= "" then self:set_status_filter(arg); return true end
    if cmd == "tagdoc" and arg ~= "" then self:open_tag(arg); return true end

    Logger.warn("todos_view", "unknown_link", { uri = uri })
    return false
end

function TodosView:_teardown()
    local widget = self.widget
    if not widget then return end
    self.widget = nil
    widget._closing = true
    widget.on_close = nil
    widget.on_back = nil
    pcall(function() UIManager:close(widget) end)
end

function TodosView:set_todos_page(page)
    local n = tonumber(page) or 1
    if n < 1 then n = 1 end
    self.todos_page = n
    if self.last_state then
        self:show({ state = self.last_state, allow_network = false })
    end
end

function TodosView:set_refreshing(refreshing)
    self.refreshing = refreshing and true or false
    if not self.widget or not self.last_state then return end
    local state = {}
    for k, v in pairs(self.last_state) do state[k] = v end
    state.refreshing = self.refreshing
    self:show({ state = state, allow_network = false })
end

function TodosView:_shell_close()
    self.widget = nil
    if self.actions then
        self.actions:dispatch("close", { source = "todos", todos = self })
    end
end

function TodosView:show(opts)
    opts = opts or {}
    self:_teardown()
    local state
    if opts.state then
        state = {}
        for k, v in pairs(opts.state) do state[k] = v end
    else
        state = self:build_state(opts)
    end
    if opts.refreshing ~= nil then state.refreshing = opts.refreshing == true end
    self.refreshing = state.refreshing == true
    if opts.refresh_hint then state.refresh_hint = opts.refresh_hint end
    self.last_state = state

    local now = os.time()
    local clock_24h = self.config and self.config:get("ui_clock_24h") == true
    local function build_model(rows)
        return DashboardModel.build_todos(state, {
            now = now,
            clock_24h = clock_24h,
            task_rows = rows,
            todos_page = self.todos_page,
            tag_filter = self.tag_filter,
            status_filter = self.status_filter,
            due_days = self.config and self.config:get("todos_due_soon_days") or nil,
            show_tags = (not self.config) or self.config:get("todos_include_tags") ~= false,
        })
    end
    local model = build_model(nil)
    local current_model = model

    local shell = Shell:new{
        title = "TODO'S",
        config = self.config,
        on_close = function() self:_shell_close() end,
        on_layout_change = function()
            self:show({ state = self.last_state, allow_network = false })
        end,
        header_factory = function(width, parent)
            return DashboardHeader:new{
                title = "TODO'S",
                config = self.config,
                plugin_dir = self.plugin_dir,
                show_parent = parent,
                on_settings = function() self:handle_link("kh:settings") end,
                on_close = function() self:handle_link("kh:close") end,
            }
        end,
        body_factory = function(width, height, parent)
            local body = TodosBody.build(model, self.config, width, height, {
                show_parent = parent,
                plugin_dir = self.plugin_dir,
                model_for = build_model,
                on_refresh = function() self:handle_link("kh:refresh") end,
                on_add = function() self:handle_link("kh:todos:add") end,
                on_toggle = function(id) self:handle_link("kh:todos:toggle:" .. id) end,
                on_rename = function(id) self:handle_link("kh:todos:rename:" .. id) end,
                on_delete = function(id) self:handle_link("kh:todos:delete:" .. id) end,
                on_details = function(id) self:show_details(id) end,
                on_edit_details = function(id) self:handle_link("kh:todos:details:" .. id) end,
                on_tag = function(tag) self:handle_link("kh:todos:tag:" .. tag) end,
                on_status = function(status) self:handle_link("kh:todos:status:" .. status) end,
                on_tag_doc = function(tag) self:handle_link("kh:todos:tagdoc:" .. tag) end,
                on_nav = function(name) self:handle_link("kh:nav:" .. name) end,
                on_next_page = function()
                    local pages = current_model.todos and current_model.todos.pages or 0
                    self:set_todos_page((self.todos_page % math.max(pages, 1)) + 1)
                end,
                on_prev_page = function()
                    local pages = current_model.todos and current_model.todos.pages or 0
                    self:set_todos_page(((self.todos_page - 2) % math.max(pages, 1)) + 1)
                end,
            })
            current_model = body.model or model
            self.model = current_model
            return body
        end,
    }
    self.widget = shell
    shell:show()
    if current_model and current_model.todos and current_model.todos.page then
        self.todos_page = current_model.todos.page
    end
    Logger.info("todos_view", "shown", {
        tasks = current_model.todos and #current_model.todos.items or 0,
        tags = current_model.todos and #current_model.todos.tags or 0,
        filter = current_model.todos and current_model.todos.active_tag or nil,
        status = current_model.todos and current_model.todos.active_status or nil,
        rows = current_model.todos and current_model.todos.page_size or nil,
        native = true,
    })
end

function TodosView:refresh(opts)
    opts = opts or {}
    if opts.reset_page then self.todos_page = 1 end
    Logger.info("todos_view", "refresh", { allow_network = opts.allow_network })
    self:show(opts)
end

function TodosView:close()
    self:_teardown()
    Logger.info("todos_view", "closed")
end

return TodosView
