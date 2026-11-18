#!/usr/bin/env bash
# Structural invariants for kindlehome.koplugin (cheap regression guards).
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# 1) Scrolling repaints must target the top-level Shell (the widget in
#    _window_stack); UIManager:setDirty on a nested widget only flashes.
#    The dashboard fits one screen and uses ScrollableContainer only as a
#    measured fallback; the article fallback uses the plugin-local paginated
#    pager; KOReader's ScrollHtmlWidget is banned.
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
if ! grep -q 'if root:getSize().h <= viewport_h then' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must measure content before deciding to scroll"
    fail=1
fi
if ! grep -q 'if root:getSize().h > viewport_h then' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must keep native scroll as a last-resort fallback"
    fail=1
fi
if ! grep -q 'ScrollableContainer:new{' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must keep native scroll as measured fallback"
    fail=1
fi
if ! grep -q 'body.fits = scroll == nil' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must expose the fit/no-scroll state"
    fail=1
fi
if ! grep -q 'local PAGE_SIZE_CHOICES = { 4, 3, 2, 1 }' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'body.page_size = chosen_size' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must degrade rows before showing the scroll bar"
    fail=1
fi
if ! grep -q 'HorizontalGroup:new{ align = "top" }' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'HorizontalSpan:new{ width = Theme.margin(config) }' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'VerticalSpan:new{ width = math.max(0, viewport_h - row:getSize().h) }' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard content must be top-left anchored with symmetric margins"
    fail=1
fi
if grep -q 'viewport = LeftContainer' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: LeftContainer would vertically center the dashboard content"
    fail=1
fi
if grep -q 'Last refreshed' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: Last refreshed must live in the stories header, not as a body section"
    fail=1
fi
if ! grep -q 'local PAGE_SIZE = 4' kindlehome.koplugin/lib/dashboard_model.lua; then
    echo "FAIL: Top Stories must prefer 4 items per page"
    fail=1
fi
if ! grep -q 'redundant_notice' kindlehome.koplugin/lib/dashboard_model.lua; then
    echo "FAIL: global hint must suppress duplicated per-source notices"
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

if ! grep -q 'callback = function() main_instance:onKindlehomeShowDashboard() end' \
        kindlehome.koplugin/ui/menus.lua \
    || grep -A4 'menu_items.kindlehome = {' kindlehome.koplugin/ui/menus.lua \
        | grep -q 'sub_item_table'; then
    echo "FAIL: Tools entry must open the dashboard directly (no settings submenu)"
    fail=1
fi
if ! grep -q 'require("ui/widget/touchmenu")' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'function Menus:settings_items' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'function Menus:show_settings' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'Menus:show_settings(self)' kindlehome.koplugin/main.lua; then
    echo "FAIL: settings must be a TouchMenu opened from the dashboard"
    fail=1
fi
if ! grep -q 'tab_item_table = { items }' kindlehome.koplugin/ui/menus.lua \
    || grep -q 'item_table = Menus:settings_items' kindlehome.koplugin/ui/menus.lua; then
    echo "FAIL: TouchMenu tab must be the settings array itself (no nested item_table)"
    fail=1
fi
if [ -f kindlehome.koplugin/ui/widget/modal_panel.lua ] \
    || grep -Eq 'modal_panel|FrameContainer|getWidth\(\) \* 0\.8' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'require("ui/widget/container/centercontainer")' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'CenterContainer:new' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'covers_header = true' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'ignore = "height"' kindlehome.koplugin/ui/menus.lua \
    || ! grep -q 'width = screen:getWidth()' kindlehome.koplugin/ui/menus.lua \
    || grep -q 'TapCloseAllMenus = nil' kindlehome.koplugin/ui/menus.lua; then
    echo "FAIL: settings must be a native full-screen TouchMenu in a CenterContainer"
    fail=1
fi
if ! grep -q 'alpha = self.alpha' kindlehome.koplugin/ui/widget/tap_icon.lua \
    || ! grep -q 'alpha = true' kindlehome.koplugin/ui/widget/stories_card.lua \
    || ! grep -q 'alpha = self.active' kindlehome.koplugin/ui/widget/bottom_nav.lua; then
    echo "FAIL: inverse icon assets must keep alpha or they flatten to white and vanish"
    fail=1
fi
for icon in prev.svg prev-inverse.svg next.svg next-inverse.svg; do
    if [ ! -f "kindlehome.koplugin/assets/icons/action/$icon" ]; then
        echo "FAIL: missing pager icon asset action/$icon"
        fail=1
    fi
done
if ! grep -q 'on_prev_page' kindlehome.koplugin/ui/widget/stories_card.lua \
    || ! grep -q 'on_prev_page' kindlehome.koplugin/ui/dashboard.lua \
    || ! grep -q 'set_refreshing(true)' kindlehome.koplugin/main.lua \
    || ! grep -q 'function Dashboard:set_refreshing' kindlehome.koplugin/ui/dashboard.lua \
    || ! grep -q 'refreshing = state.refreshing == true' kindlehome.koplugin/lib/dashboard_model.lua \
    || ! grep -q 'hero.refreshing' kindlehome.koplugin/ui/widget/hero_weather.lua; then
    echo "FAIL: previous-page control and visible refresh feedback must stay wired"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: plugin invariants (native scroll bodies, opaque shell, top-level repaint target, menu registration, streamed downloads, safe content root, sharp dashboard widgets, in-dashboard settings, visible pager icons)"
fi
exit "$fail"
