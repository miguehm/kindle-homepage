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
if ! grep -q 'bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)' kindlehome.koplugin/ui/shell.lua; then
    echo "FAIL: Shell must paint an opaque full-screen background (stale pixels in title area)"
    fail=1
fi
if ! grep -q 'show_parent = self' kindlehome.koplugin/ui/shell.lua; then
    echo "FAIL: TitleBar must use the Shell as repaint target"
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

# 6) The custom content folder must be sanitized in config and resolved only
#    through paths.lua (never hard-coded in the UI layer).
if ! grep -q 'custom_content_dir' kindlehome.koplugin/lib/config.lua \
        || ! grep -q 'sanitize_custom_dir' kindlehome.koplugin/lib/config.lua \
        || ! grep -q 'custom_content_dir' kindlehome.koplugin/lib/paths.lua; then
    echo "FAIL: custom content folder must be sanitized in config and resolved in paths.lua"
    fail=1
fi
if grep -rn '"/mnt/us/documents"' --include='*.lua' kindlehome.koplugin/ui >/dev/null; then
    echo "FAIL: UI must not hard-code the content root; go through paths.lua"
    fail=1
fi
if ! grep -q 'require("ui/widget/pathchooser")' kindlehome.koplugin/ui/menus.lua \
        || ! grep -q 'reset_custom_content_dir' kindlehome.koplugin/ui/menus.lua; then
    echo "FAIL: custom content folder must use the native PathChooser and offer Reset"
    fail=1
fi

# 7) Paperwhite redesign: modular native widgets, sharp edges and monochrome
#    icon assets must stay present so the dashboard cannot silently fall back
#    to the old stacked-card layout.
for widget in dashboard_header bottom_nav hero_weather stories_card battery_glyph tap_icon tap_row design_text; do
    if [ ! -f "kindlehome.koplugin/ui/widget/$widget.lua" ]; then
        echo "FAIL: missing dashboard widget ui/widget/$widget.lua"
        fail=1
    fi
done
if ! grep -q 'DashboardHeader' kindlehome.koplugin/ui/dashboard.lua \
    || ! grep -q 'BottomNav' kindlehome.koplugin/ui/dashboard_body.lua \
    || ! grep -q 'HeroWeather' kindlehome.koplugin/ui/dashboard_body.lua \
    || ! grep -q 'StoriesCard' kindlehome.koplugin/ui/dashboard_body.lua \
    || ! grep -q 'getCropRegion' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard must wire the custom header, fixed nav, hero, stories and crop region"
    fail=1
fi
if [ ! -d kindlehome.koplugin/assets/icons/weather ] || [ ! -d kindlehome.koplugin/assets/icons/nav ] \
    || [ ! -d kindlehome.koplugin/assets/icons/action ]; then
    echo "FAIL: monochrome icon asset directories are missing"
    fail=1
fi
if grep -rn 'radius[[:space:]]*=' --include='*.lua' \
        kindlehome.koplugin/ui/widget/dashboard_header.lua \
        kindlehome.koplugin/ui/widget/bottom_nav.lua \
        kindlehome.koplugin/ui/widget/hero_weather.lua \
        kindlehome.koplugin/ui/widget/stories_card.lua \
        kindlehome.koplugin/ui/dashboard_body.lua >/dev/null; then
    echo "FAIL: dashboard widgets must keep sharp (0px) corners"
    fail=1
fi
if ! grep -q 'ui_clock_24h' kindlehome.koplugin/lib/config.lua; then
    echo "FAIL: 12/24h clock setting missing from config"
    fail=1
fi
if ! grep -q 'Widget:extend' kindlehome.koplugin/ui/widget/battery_glyph.lua; then
    echo "FAIL: battery glyph must be a real Widget (it receives touch events)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: plugin invariants (native scroll bodies, opaque shell, top-level repaint target, menu registration, streamed downloads, safe content root, sharp dashboard widgets)"
fi
exit "$fail"
