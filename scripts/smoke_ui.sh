#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Offline UI smoke test (Lua 5.1): builds the native dashboard/article widget
# trees with stubbed KOReader modules and asserts model, layout and action wiring.
set -u
cd "$(dirname "$0")/.." || exit 2

plugin_dir="$(pwd)/kindlehome.koplugin"
lua_bin="${LUA:-}"
if [ -z "$lua_bin" ]; then
    for candidate in lua5.1 luajit lua; do
        if command -v "$candidate" >/dev/null 2>&1; then lua_bin="$candidate"; break; fi
    done
fi
if [ -z "$lua_bin" ]; then
    echo "SKIP: no lua5.1/luajit/lua found"
    exit 0
fi

status=0
root_dir="$(pwd)"
for test_file in scripts/smoke/dashboard.lua scripts/smoke/todos.lua scripts/smoke/article_view.lua scripts/smoke/article_pager.lua scripts/smoke/shell.lua scripts/smoke/shell_paint.lua scripts/smoke/action_bar.lua scripts/smoke/md_render.lua scripts/smoke/article_download.lua scripts/smoke/hnmd_url.lua scripts/smoke/todos_client.lua scripts/smoke/http_stream.lua scripts/smoke/todos_http.lua scripts/smoke/todos_state.lua scripts/smoke/ui_state.lua scripts/smoke/config.lua scripts/smoke/menus.lua scripts/smoke/paths.lua scripts/smoke/link_card.lua scripts/smoke/weather.lua scripts/smoke/http_conditional.lua scripts/smoke/todos_conflict.lua scripts/smoke/todos_pagination.lua scripts/smoke/hnmd_conditional.lua; do
    if ! ( cd "$plugin_dir" && LUA_PATH="./?.lua;;" "$lua_bin" "$root_dir/$test_file" "$plugin_dir" ); then
        echo "FAIL: $test_file"
        status=1
    fi
done
if [ "$status" -eq 0 ]; then
    echo "OK: UI smoke tests ($lua_bin)"
fi
exit "$status"
