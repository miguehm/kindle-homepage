#!/usr/bin/env bash
# Offline UI smoke test (Lua 5.1): builds the dashboard/article HTML with
# stubbed KOReader modules and asserts link wiring + ScrollHtmlWidget options.
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
for test_file in scripts/smoke/dashboard.lua scripts/smoke/article_view.lua scripts/smoke/article_pager.lua scripts/smoke/shell.lua scripts/smoke/action_bar.lua scripts/smoke/md_render.lua scripts/smoke/article_download.lua scripts/smoke/hnmd_url.lua scripts/smoke/http_stream.lua; do
    if ! ( cd "$plugin_dir" && LUA_PATH="./?.lua;;" "$lua_bin" "$root_dir/$test_file" "$plugin_dir" ); then
        echo "FAIL: $test_file"
        status=1
    fi
done
if [ "$status" -eq 0 ]; then
    echo "OK: UI smoke tests ($lua_bin)"
fi
exit "$status"
