-- SPDX-License-Identifier: MIT
local M = {}

local MAP = {
    offline = "Offline. Turn on WiFi and refresh.",
    timeout = "Network timeout. Showing cached data if available.",
    network = "Network error. Showing cached data if available.",
    http_401 = "Invalid API key. Check HN settings.",
    http_404 = "Article not available on the server.",
    http_503 = "hnmd server is starting, try again in a few minutes.",
    http_other = "Service unavailable. Try again later.",
    parse = "Data error. Try refreshing.",
    too_large = "Response too large. Try refreshing later.",
    incomplete = "Download incomplete. Try again.",
    no_content = "No article content for this item.",
    warming_up = "Article is still being prepared. Try again shortly.",
    offline_no_local = "Offline and no local copy. Turn on WiFi to download.",
    budget_exceeded = "Refresh budget exceeded. Showing cached data.",
    configure_location = "Set weather location in settings.",
    no_markdown = "No markdown available for this item.",
    content_unavailable = "Content unavailable.",
    corrupted_file = "Content file is unavailable or corrupted.",
    not_found = "Content not found.",
    downloading = "Downloading article…",
    path_invalid = "Use an absolute path such as /mnt/us/My Docs. Paths with '..' are not allowed.",
    path_saved = "Custom content folder saved.",
    path_reset = "Custom content folder cleared. Using the default location.",
    coming_soon = "Coming soon.",
    todos_empty = "No tasks yet. Add one with +.",
    todos_created = "Task added.",
    todos_updated = "Task updated.",
    todos_deleted = "Task deleted.",
    todos_write_forbidden = "Writes are disabled on the server. Check API keys or TODO_ALLOW_INSECURE_WRITES.",
    todos_invalid_text = "Enter a task description.",
    todos_invalid_tags = "Invalid tag. Use letters, numbers, '-' or '_' (max 10).",
    todos_no_changes = "No changes.",
    todos_write_failed = "Could not save the task. Try again.",
    todos_details_saved = "Task details saved.",
    todos_details_invalid = "Details must be at most 1000 bytes.",
    todos_no_details = "No details for this task.",
    todos_unavailable = "TODO'S unavailable.",
    settings_unavailable = "Open Kindle Home settings from the dashboard gear.",
    path_unwritable = "Folder saved, but it could not be created. Check the path and permissions.",
}

function M.for_kind(kind, fallback)
    if type(kind) ~= "string" or kind == "" then
        return fallback
    end
    return MAP[kind] or fallback
end

function M.refresh_result(kind)
    return M.for_kind(kind, "Refresh issue. Showing cached data if available.")
end

function M.weather(kind, status)
    if status == "configure_location" then return MAP.configure_location end
    if kind == "offline" or kind == "timeout" or kind == "network" then return MAP[kind] end
    if kind == "http_other" or kind == "http_503" then return MAP.http_other end
    if kind == "parse" or kind == "too_large" then return MAP[kind] end
    if kind == "budget_exceeded" then return MAP.budget_exceeded end
    if status == "error" then return "Weather unavailable." end
    if status == "stale" then return "Showing cached weather." end
    return nil
end

function M.hn(kind, status, has_cache)
    if kind == "http_401" then return MAP.http_401 end
    if kind == "http_503" then return MAP.http_503 end
    if kind == "offline" or kind == "timeout" or kind == "network" then
        return has_cache and "Offline or network error. Showing cached HN." or "Offline or network error. Turn on WiFi and refresh."
    end
    if kind == "parse" or kind == "too_large" then return MAP[kind] end
    if kind == "budget_exceeded" then return MAP.budget_exceeded end
    if status == "stale" then return "Showing cached HN data." end
    if status == "error" then return "HN unavailable." end
    return nil
end

function M.todos(kind, status, has_cache)
    if kind == "http_401" then return MAP.http_401 end
    if kind == "http_503" then return MAP.http_503 end
    if kind == "offline" or kind == "timeout" or kind == "network" then
        return has_cache and "Offline or network error. Showing cached TODO'S."
            or "Offline or network error. Turn on WiFi and refresh."
    end
    if kind == "parse" or kind == "too_large" then return MAP[kind] end
    if kind == "budget_exceeded" then return MAP.budget_exceeded end
    if status == "stale" then return "Showing cached TODO'S." end
    if status == "error" then return MAP.todos_unavailable end
    return nil
end

function M.todos_write(res)
    if not res or res.ok then return nil end
    if res.error_kind == "http_401" then return MAP.http_401 end
    if res.status == 403 then return MAP.todos_write_forbidden end
    if res.error_kind == "invalid_tags" then return MAP.todos_invalid_tags end
    if res.status == 400 or res.error_kind == "invalid_text" then return MAP.todos_invalid_text end
    if res.status == 413 then return MAP.too_large end
    if res.status == 404 then return MAP.not_found end
    if res.error_kind == "http_503" then return MAP.http_503 end
    if res.error_kind == "timeout" or res.error_kind == "network" then return MAP.todos_write_failed end
    if res.error_kind == "parse" then return MAP.parse end
    return MAP.todos_write_failed
end

function M.reading(kind)
    return MAP[kind] or MAP.content_unavailable
end

return M
