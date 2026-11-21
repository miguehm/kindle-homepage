#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Syntax gate for the runtime KOReader actually uses on Kindle: Lua 5.1 / LuaJIT.
# `luac` from recent distros (5.3/5.4/5.5) accepts syntax that fails on device
# (e.g. bitwise operators such as `~`), so it must not be used as the only check.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
check_file() {
    local f="$1"
    case "$engine" in
        luac5.1) luac5.1 -p "$f" >/dev/null 2>&1 ;;
        lua5.1)  lua5.1 -e "assert(loadfile([[$f]]))" >/dev/null 2>&1 ;;
        luajit)  luajit -e "assert(loadfile([[$f]]))" >/dev/null 2>&1 ;;
    esac
}

if command -v luac5.1 >/dev/null 2>&1; then
    engine="luac5.1"
elif command -v lua5.1 >/dev/null 2>&1; then
    engine="lua5.1"
elif command -v luajit >/dev/null 2>&1; then
    engine="luajit"
else
    echo "error: no Lua 5.1 compatible engine found (install lua5.1 or luajit)" >&2
    echo "       note: system 'luac' (5.3+) is not a substitute for this check" >&2
    exit 2
fi

while IFS= read -r f; do
    if ! check_file "$f"; then
        echo "FAIL: $f"
        case "$engine" in
            luac5.1) luac5.1 -p "$f" 2>&1 | sed 's/^/  /' ;;
            *)       "$engine" -e "assert(loadfile([[$f]]))" 2>&1 | sed 's/^/  /' ;;
        esac
        fail=1
    fi
done < <(find kindlehome.koplugin -name '*.lua' | sort)

if [ "$fail" -eq 0 ]; then
    echo "OK: all kindlehome.koplugin Lua files parse as Lua 5.1 ($engine)"
fi
exit "$fail"
