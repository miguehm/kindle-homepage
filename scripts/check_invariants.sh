#!/usr/bin/env bash
# Structural invariants for kindlehome.koplugin (cheap regression guards).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# 1) Scrolling repaints must target the top-level Shell (the widget in
#    _window_stack); UIManager:setDirty on a nested widget only flashes.
#    The dashboard uses ScrollableContainer and the article fallback uses the
#    plugin-local paginated pager; KOReader's ScrollHtmlWidget is banned.
for field in dialog show_parent; do
    if ! grep -q "self\.body\.$field = self" kindlehome.koplugin/ui/shell.lua; then
        echo "FAIL: Shell must wire self.body.$field = self (top-level repaint target)"
        fail=1
    fi
done
if grep -rn '\.dialog[[:space:]]*=' --include='*.lua' \
        kindlehome.koplugin/ui/dashboard.lua kindlehome.koplugin/ui/article_view.lua >/dev/null; then
    echo "FAIL: body widgets must not self-assign dialog; Shell wires it to itself"
    fail=1
fi
if grep -n 'ScrollHtmlWidget\|dashboard_html\|DashboardHtml' kindlehome.koplugin/ui/dashboard.lua >/dev/null; then
    echo "FAIL: dashboard must use the native body, not HTML/ScrollHtmlWidget"
    fail=1
fi
if ! grep -q 'ScrollableContainer' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must scroll with ScrollableContainer"
    fail=1
fi
if [ -e kindlehome.koplugin/lib/render/dashboard_html.lua ]; then
    echo "FAIL: dead lib/render/dashboard_html.lua must be removed"
    fail=1
fi
if grep -rn 'ScrollHtmlWidget' --include='*.lua' kindlehome.koplugin >/dev/null; then
    echo "FAIL: ScrollHtmlWidget must not be used (native scroll bodies only)"
    fail=1
fi
if ! grep -q 'HtmlBoxWidget' kindlehome.koplugin/ui/article_html_pager.lua \
        || ! grep -q 'VerticalScrollBar' kindlehome.koplugin/ui/article_html_pager.lua; then
    echo "FAIL: article pager must use HtmlBoxWidget + VerticalScrollBar"
    fail=1
fi

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
    echo "OK: plugin invariants (native scroll bodies, top-level repaint target, menu registration, streamed downloads)"
fi
exit "$fail"
