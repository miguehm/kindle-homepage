#!/usr/bin/env bash
# Structural invariants for kindlehome.koplugin (cheap regression guards).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# 1) ScrollHtmlWidget scroll handlers touch self.dialog.movable; a widget
#    created without `dialog` crashes KOReader on the first swipe/tap.
widget_files=$(grep -rl "ScrollHtmlWidget:new" --include='*.lua' kindlehome.koplugin || true)
if [ -z "$widget_files" ]; then
    echo "FAIL: no ScrollHtmlWidget usage found (unexpected; check paths)"
    fail=1
fi

while IFS= read -r file; do
    [ -n "$file" ] || continue
    awk -v f="$file" '
        { lines[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++) {
                if (lines[i] ~ /ScrollHtmlWidget:new/) {
                    found = 0
                    for (j = i; j <= i + 25 && j <= NR; j++) {
                        if (lines[j] ~ /dialog[[:space:]]*=/) { found = 1; break }
                        if (j > i && lines[j] ~ /UIManager:show/) { break }
                    }
                    if (!found) {
                        printf "FAIL: %s:%d ScrollHtmlWidget:new without dialog\n", f, i
                        exit 1
                    }
                }
            }
        }
    ' "$file" || fail=1
done <<< "$widget_files"

# 2) KOReader has no ui/elements/menu_items module; menus must be registered
#    from addToMainMenu(menu_items).
if grep -rn 'ui/elements/menu_items' --include='*.lua' kindlehome.koplugin >/dev/null; then
    echo "FAIL: ui/elements/menu_items does not exist in KOReader"
    fail=1
fi

# 3) Article bodies are streamed to disk (PW5 has ~15 MB free RAM): the hnmd
#    client must use the file sink, not the in-memory getter.
if ! grep -q 'Http\.get_to_file' kindlehome.koplugin/lib/hnmd.lua; then
    echo "FAIL: lib/hnmd.lua must download article bodies via Http.get_to_file"
    fail=1
fi

# 4) UI code never performs HTTP or filesystem deletion directly.
if grep -rn 'Http\.get' --include='*.lua' kindlehome.koplugin/ui >/dev/null; then
    echo "FAIL: ui/ must not call Http directly (go through hnmd/article_store)"
    fail=1
fi
if grep -rn 'os\.remove\|os\.rename' --include='*.lua' kindlehome.koplugin/ui >/dev/null; then
    echo "FAIL: ui/ must not delete/rename files directly"
    fail=1
fi

# 5) Inside article_store, cleanup only touches ".tmp" paths.
bad_fs=$(grep -n 'os\.remove\|os\.rename' kindlehome.koplugin/lib/article_store.lua | grep -v 'tmp' || true)
if [ -n "$bad_fs" ]; then
    echo "FAIL: article_store may only remove/rename .tmp paths:"
    echo "$bad_fs"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: plugin invariants (ScrollHtmlWidget dialog, menu registration, streamed downloads)"
fi
exit "$fail"
