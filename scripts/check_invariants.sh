#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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
if ! grep -q 'fits = measured_root:getSize().h <= viewport_h' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must measure content before deciding to scroll"
    fail=1
fi
if ! grep -q 'if not chosen then' kindlehome.koplugin/ui/dashboard_body.lua; then
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
if ! grep -q 'local DEFAULT_PAGE_SIZE = 4' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'local function measure(page_size)' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'while lo <= hi do' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'body.page_size = chosen_size' kindlehome.koplugin/ui/dashboard_body.lua \
        || ! grep -q 'body.probes = probes' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard_body must measure a configurable preferred size and degrade to fit before scrolling"
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
if grep -q '<img' kindlehome.koplugin/lib/render/md_to_html.lua; then
    echo "FAIL: Markdown images must not be embedded as <img>"
    fail=1
fi
if ! grep -q 'sanitize_href(url)' kindlehome.koplugin/lib/render/md_to_html.lua; then
    echo "FAIL: Markdown image URLs must pass through the href sanitizer"
    fail=1
fi

# 2) KOReader has no ui/elements/menu_items module; menus must be registered
#    from addToMainMenu(menu_items).
if grep -rn 'ui/elements/menu_items' --include='*.lua' kindlehome.koplugin >/dev/null; then
    echo "FAIL: ui/elements/menu_items does not exist in KOReader"
    fail=1
fi

# 3) Article bodies are streamed to disk (e-ink devices have very little free
#    RAM): the hnmd client must use the file sink, not the in-memory getter.
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

# 5) Inside article_store, cleanup only touches ".tmp" paths and marked derived HTML.
bad_fs=$(grep -n 'os\.remove\|os\.rename' kindlehome.koplugin/lib/article_store.lua \
    | grep -v 'tmp' | grep -v 'ephemeral cleanup: derived HTML only' || true)
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
if ! grep -q 'CenterContainer:new{' kindlehome.koplugin/ui/widget/dashboard_header.lua \
    || ! grep -q 'max_width = title_limit' kindlehome.koplugin/ui/widget/dashboard_header.lua; then
    echo "FAIL: dashboard header must center its row vertically and bound the title"
    fail=1
fi
header_margins=$(grep -c 'HorizontalSpan:new{ width = margin }' kindlehome.koplugin/ui/widget/dashboard_header.lua || true)
if [ "${header_margins:-0}" -lt 2 ]; then
    echo "FAIL: dashboard header must use symmetric leading and trailing margins"
    fail=1
fi
if ! grep -q 'Theme.icon_file(self.plugin_dir, "header", "settings"' kindlehome.koplugin/ui/widget/dashboard_header.lua \
    || ! grep -q 'Theme.icon_file(self.plugin_dir, "header", "close"' kindlehome.koplugin/ui/widget/dashboard_header.lua; then
    echo "FAIL: dashboard header icons must use the normalized header assets"
    fail=1
fi
for icon in settings.svg close.svg; do
    if [ ! -f "kindlehome.koplugin/assets/icons/header/$icon" ]; then
        echo "FAIL: missing header icon asset header/$icon"
        fail=1
    fi
done
if ! grep -q 'function StoriesCard.apply_fill' kindlehome.koplugin/ui/widget/stories_card.lua \
    || ! grep -q 'fill_height' kindlehome.koplugin/ui/widget/stories_card.lua; then
    echo "FAIL: stories card must support a fixed fill height with a bottom-anchored pager"
    fail=1
fi
if ! grep -q 'StoriesCard.apply_fill(card' kindlehome.koplugin/ui/dashboard_body.lua; then
    echo "FAIL: dashboard body must give the leftover viewport height to the stories card"
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

# 8) Top Stories rows are configurable (1-10, default 4) and the page persists
#    across restarts; only explicit user refreshes reset it.
if [ ! -f kindlehome.koplugin/lib/ui_state.lua ] \
        || ! grep -q 'atomic_write' kindlehome.koplugin/lib/ui_state.lua \
        || ! grep -q 'ui_state' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'get_hn_page' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'set_hn_page' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'hn_items_per_page' kindlehome.koplugin/lib/config.lua \
        || ! grep -q 'hn_items_per_page' kindlehome.koplugin/ui/menus.lua \
        || ! grep -q 'reset_hn_page' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'reset_page' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'reset_page' kindlehome.koplugin/main.lua \
        || ! grep -q 'reset_page = false' kindlehome.koplugin/main.lua; then
    echo "FAIL: Top Stories rows must be configurable and the page must persist; only explicit refreshes reset it"
    fail=1
fi

# 9) Derived article HTML is ephemeral: cached outside the content folder,
#    removed on reader/fallback close, and legacy adjacent .html is migrated.
if ! grep -q 'ephemeral_articles_dir' kindlehome.koplugin/lib/paths.lua \
        || ! grep -q 'cache_dir' kindlehome.koplugin/lib/paths.lua \
        || ! grep -q 'remove_ephemeral' kindlehome.koplugin/lib/article_store.lua \
        || ! grep -q 'cleanup_legacy_html' kindlehome.koplugin/lib/article_store.lua \
        || ! grep -q 'on_cleanup' kindlehome.koplugin/ui/article_view.lua \
        || ! grep -q 'on_cleanup' kindlehome.koplugin/ui/dashboard.lua; then
    echo "FAIL: derived article HTML must be ephemeral (cache render, close cleanup, legacy migration)"
    fail=1
fi

# 10) TODO'S module: JSON read + local tag filter, writes via lib/todos only,
#     on-demand per-tag Markdown via the native article chain.
if ! grep -q 'function Http.post_json' kindlehome.koplugin/lib/http.lua \
        || ! grep -q 'function Http.patch_json' kindlehome.koplugin/lib/http.lua \
        || ! grep -q 'function Http.delete' kindlehome.koplugin/lib/http.lua \
        || ! grep -q 'function Todos.fetch_index' kindlehome.koplugin/lib/todos.lua \
        || ! grep -q 'function TodosState.invalidate' kindlehome.koplugin/lib/todos_state.lua \
        || ! grep -q 'todos_ttl_minutes' kindlehome.koplugin/lib/config.lua \
        || ! grep -q 'dispatch("nav"' kindlehome.koplugin/ui/dashboard.lua \
        || ! grep -q 'ui/todos.lua' kindlehome.koplugin/main.lua \
        || ! grep -q 'kh:todos:tagdoc:' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q 'force = true' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q 'cre.render.reload' kindlehome.koplugin/ui/widget/todos_card.lua \
        || ! grep -q 'allow_newline = true' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q 'multiinputdialog' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q 'function TagChips.build' kindlehome.koplugin/ui/widget/tag_chips.lua \
        || ! grep -q 'function TagChips.build_status' kindlehome.koplugin/ui/widget/tag_chips.lua \
        || ! grep -q 'kh:todos:status:' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q 'status_filter' kindlehome.koplugin/lib/dashboard_model.lua \
        || ! grep -q 'function Todos.merge_payload' kindlehome.koplugin/lib/todos.lua \
        || ! grep -q 'function TodosState.apply' kindlehome.koplugin/lib/todos_state.lua \
        || ! grep -q 'json_options' kindlehome.koplugin/lib/http.lua; then
    echo "FAIL: TODO'S module wiring incomplete"
    fail=1
fi
if ! grep -q 'Theme.icon_file(callbacks.plugin_dir, "action", "refresh")' \
        kindlehome.koplugin/ui/widget/todos_card.lua \
        || ! grep -q 'Theme.icon_file(plugin_dir, "action", "refresh")' \
        kindlehome.koplugin/ui/widget/stories_card.lua \
        || [ ! -f kindlehome.koplugin/assets/icons/action/refresh.svg ]; then
    echo "FAIL: refresh control must use the two-arrow cycle asset in TODO'S and Top Stories"
    fail=1
fi
if ! grep -q 'TodosCard.apply_fill(card' kindlehome.koplugin/ui/todos_body.lua \
        || ! grep -q 'function TodosCard.apply_fill' kindlehome.koplugin/ui/widget/todos_card.lua; then
    echo "FAIL: TODO'S card must absorb the leftover viewport height"
    fail=1
fi
if ! grep -q 'ui/widget/datetimewidget' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q '_("Today")' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q '_("Tomorrow")' kindlehome.koplugin/ui/todos.lua \
        || ! grep -q '_("+1 week")' kindlehome.koplugin/ui/todos.lua; then
    echo "FAIL: due date presets and native picker must stay wired"
    fail=1
fi
if ! grep -q 'todos_due_soon_days' kindlehome.koplugin/lib/config.lua \
        || ! grep -q 'due_date' kindlehome.koplugin/lib/todos.lua \
        || ! grep -q 'due_soon' kindlehome.koplugin/lib/dashboard_model.lua \
        || ! grep -q 'Due date (optional)' kindlehome.koplugin/ui/todos.lua; then
    echo "FAIL: TODO'S deadline support (config, client, model and modal) incomplete"
    fail=1
fi
if ! grep -q 'chip.label .. ": "' kindlehome.koplugin/ui/widget/tag_chips.lua; then
    echo "FAIL: filter chips must show a colon before the count"
    fail=1
fi
if [ ! -f kindlehome.koplugin/assets/icons/action/eye.svg ] \
        || [ ! -f kindlehome.koplugin/assets/icons/action/plus.svg ] \
        || ! grep -q 'Theme.icon_file(callbacks.plugin_dir, "action", "eye")' \
            kindlehome.koplugin/ui/widget/todos_card.lua \
        || ! grep -q 'Theme.icon_file(callbacks.plugin_dir, "action", "plus")' \
            kindlehome.koplugin/ui/widget/todos_card.lua \
        || ! grep -q 'HoldChip' kindlehome.koplugin/ui/widget/tag_chips.lua; then
    echo "FAIL: TODO'S eye/plus icon assets and long-press tag Markdown opener are missing"
    fail=1
fi
if grep -q 'book.opened' kindlehome.koplugin/ui/widget/tag_chips.lua; then
    echo "FAIL: tag filter chips must not render a book icon"
    fail=1
fi
if grep -rn 'Http\.' --include='*.lua' kindlehome.koplugin/ui >/dev/null; then
    echo "FAIL: ui/ must not call Http directly (go through lib/todos or article_store)"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK: plugin invariants (native scroll bodies, opaque shell, top-level repaint target, menu registration, streamed downloads, safe content root, sharp dashboard widgets, in-dashboard settings, visible pager icons, configurable Top Stories rows and persistent page, ephemeral article HTML, safe image links, todos writes, nav, refresh and details)"
fi
exit "$fail"
