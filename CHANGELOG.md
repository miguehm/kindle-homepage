# Changelog

## [2.20.1] - 2026-11-27

### Fixed
- **Dashboard did not open on Kindle** (`ffi/blitbuffer.lua: attempt to index local 'color' (a nil value)`). The new touch-slot widget compared its background color with `nil`; on LuaJIT colors are FFI cdata and that comparison runs the color's `__eq`, which raises. Colors are now tested by truthiness.
- The fallback reader no longer double-checks links with screen coordinates; `HtmlBoxWidget` already follows tapped links before the pager sees the tap.

### Added
- The UI smoke tests also run under LuaJIT with cdata colors that behave like KOReader's, and `check_invariants.sh` rejects any color compared with `nil`.

## [2.20.0] - 2026-11-27

### Changed
- **Cheaper repaints on e-ink.** Page turns, filters, the `Updating…` indicator and clock ticks swap only the section that changed and refresh only its rectangle; the hero and the bottom nav are no longer rebuilt on every page. Switching between DASHBOARD and TODO'S reuses the open screen (one non-flashing refresh instead of two full flashes) and the views' in-memory state.
- **Stable pages.** Story and task rows are measured on the longest titles/tasks, so the row count never changes while paging; the chosen count is cached per layout. Titles are capped at two lines.
- **Redesigned dashboard.** Balanced clock/weather card, freshness shown once as `Updated 10:40` in the Top Stories header, compact meta line and a `Saved` marker for downloaded stories.
- **Redesigned TODO'S.** Real checkboxes, edit/delete icons, chips that follow the design spec, and the same pager as Top Stories.
- **All visible text in English** (status chips, empty states, due dates such as `Due 27 Nov 2026`).
- **Clearer settings.** One switch per source, presets with `Custom…` for update intervals and items per page, an *Account & server* submenu for the URL, API key and server status, and notes as help text.
- **Cleaner reading view.** One title, a compact byline and two links (`Original article`, `HN discussion`); nested bullet lists.

### Added
- **Press feedback.** Tapped controls invert instantly with a fast refresh limited to the control.
- **48dp touch targets** for every icon and full-frame tappable chips.
- **Swipe left/right** to page Top Stories and TASKS.
- **Live clock** on the dashboard, updated each minute while it is visible.
- **Notice boxes with Retry** for offline and error states; a cold start says `Not loaded yet` instead of `HN unavailable`.
- **Fallback reader:** taps outside links turn the page (left third back), the page is remembered for the session, and external links are copied to the clipboard.

### Fixed
- The gap between the header's settings and close icons collapsed to 1 px.
- Icon fallbacks were always used alongside the plugin's SVGs, and done untagged tasks were counted as due soon/overdue (`x and nil or y` always returned `y`).

## [2.19.0] - 2026-11-26

### Changed
- **Minimum screen updates on every refresh.** The Shell is no longer torn down and recreated when only the content changes: paging, filters, settings repaints, refresh results and the `Updating…` indicator now swap just the body and enqueue one non-flashing `ui` refresh for that framebuffer slice. A deterministic signature of the painted state skips the repaint entirely when nothing changed — a refresh served from a still-valid cache, or a redundant `Updating…` flag toggle, costs zero screen updates. Every eighth in-place update is promoted to a full refresh to clear e-ink ghosting; opening, closing and rotation remain full refreshes.

### Added
- **Indicator only for explicit refreshes.** The `Updating…` paint is shown for manual refreshes (still forced before the blocking fetch) and skipped for automatic refreshes after a TODO'S write or on open, so those now cost a single paint of the final result.

## [2.18.0] - 2026-11-26

### Fixed
- **False overdue counts after creating a task.** `Todos.merge_payload` no longer recomputes `due_soon`/`overdue` from the cached item window. The server's global counters stay authoritative; a local write only applies deterministic `open`/`done`/`total` deltas (and per-tag deltas), so a device clock whose day differs from `todos_timezone` can no longer turn today's tasks into false "Vencidas". Creating a task with an idempotent retry now replaces the stored task instead of double counting it.

### Added
- **Automatic refresh after every TODO'S write.** Create, edit, toggle and delete schedule a server refresh (coalesced, deferred outside the dialog callback, skipped while another refresh is in progress or offline). The local merge keeps the UI immediate and works as an offline fallback; the refresh then replaces all counters with the server's real values without resetting the current page or prompting for WiFi.
- **Small clock/date line in the TASKS card.** Shows `THU, 26 NOV · 14:32` (12h/24h follows the existing setting) plus `· Updating…` while refreshing. It is rebuilt on repaint — no timer — and the adaptive row measurement keeps the card on one screen.
- **Consistent due-date presets.** `Today` / `Tomorrow` / `+1 week` and the picker now follow the device's local day when `todos_timezone` is configured (UTC otherwise), matching the server's `tz` interpretation when the Kindle clock is set to the same zone. A settings note documents this requirement.

## [2.17.0] - 2026-11-26

### Changed
- **Aligned the hnmd client with backend OpenAPI 1.5.0.** Task writes now send `If-Match` with the task's stored revision. A stale revision (`412`) or a missing precondition (`428`) refreshes the task list and asks the user to repeat the action; the plugin never silently overwrites a change made on another device. New tasks carry a client-generated `id` so a manual retry cannot create a duplicate.
- **Task lists are paginated.** `/v1/todos` is requested with `limit=500` and `next_offset` is followed up to three pages (deduplicating by task id). The server's global counters stay authoritative when the list is partial. `truncated` is now reported only as the backend's 128 KiB trim, with a separate notice for a partial list.
- **`GET /v1/top` revalidates with its weak ETag.** On `304` the cached index is kept and only its age is reset; no local data is deleted. Gzip is intentionally not negotiated: all requests send `Accept-Encoding: identity` because the Kindle HTTP path has no inflate step and validates `Content-Length`.

### Added
- **Timezone setting for TODO'S.** `todos_timezone` (Ajustes → TODO'S → *TODO'S timezone*) accepts an IANA name sent as `tz` on task requests and per-tag Markdown. Empty means the server's `TODO_TIMEZONE` (UTC by default); local due-date classification follows the device's day when a timezone is set.
- **Server status diagnostic.** Settings → Hacker News → *Server status* reports hnmd's version, readiness, auth state, task count and server time from `GET /v1/status`.
- **Unified error handling.** JSON error bodies are parsed into typed error codes and fields (`text`, `tags`, `details`, `due_date`, `tz`, `if_match`, `current_revision`), giving actionable messages for validation and revision conflicts.

## [2.16.0] - 2026-11-26

### Added
- **Top Stories remembers its page across restarts.** The current HN page is stored in `<DataDir>/cache/kindlehome/ui_state.json` (versioned, atomic write) and restored when the dashboard opens again, including after restarting KOReader or reloading the plugin. Only the in-card refresh button (and an explicit refresh action from the Dispatcher/gesture) returns to page 1; `refresh_on_open` and settings repaints keep the page. Opening offline or with an empty feed no longer overwrites the remembered page with 1. A corrupt or incompatible state file is quarantined and the page falls back to 1 without crashing.

## [2.15.0] - 2026-11-26

### Changed
- **Refresh icon is now two arrows in a cycle.** Both the TASKS header in TODO'S and Top Stories use the plugin's own `assets/icons/action/refresh.svg` instead of KOReader's `cre.render.reload` (a framed document with a tiny badge that was hard to read on e-ink). The native icon remains only as a fallback when no plugin asset path is available.
- **The TODO'S card fills the remaining viewport height.** Like Top Stories, it now absorbs the space left under the status/tag chips, so the list no longer floats at the top with a blank area below it. The pager, when present, stays bottom-anchored inside the taller card.
- **Due dates no longer need to be typed in full.** The add/edit modal adds **Today / Tomorrow / +1 week** presets and a **Pick…** button that opens KOReader's native date picker (year/month/day spinners, plus **Clear**). The `YYYY-MM-DD` field is kept for exact entry and validation; all generated dates use the same canonical UTC format. If the picker widget is unavailable, presets still work.

## [2.14.0] - 2026-11-23

### Added
- **Due dates in TODO'S.** The add/edit modal has a fourth **Due date** field (`YYYY-MM-DD`). Deadlines appear in the task row as `Vence: DD-MM-YYYY` and in the Markdown as `(vence YYYY-MM-DD)`. Open tasks with a deadline sort first by date (overdue first), matching the backend.
- **Two new status chips: Por vencer / Vencidas.** They combine with the tag filter and take their counts from the server. **Por vencer** covers today through today + *Due soon window (days)* (default **3**, configurable in Ajustes → TODO'S, 1–30); **Vencidas** covers deadlines before today. Requires backend OpenAPI 1.4.0.

### Changed
- Filter chips now show a colon before the count (`Pendientes: 5`, `#casa: 2`) instead of a bare space.

## [2.13.1] - 2026-11-22

### Fixed
- **The add-task button is a real `+` again.** KOReader's native `plus` icon is an outlined appbar shape (a hollow cross at small sizes), so the plugin now ships its own thin-stroked `assets/icons/action/plus.svg`, matching the weight of the other header icons at the larger 30 dp size.

## [2.13.0] - 2026-11-22

### Fixed
- **Tags are no longer lost when editing a task.** The edit modal now sends only the fields that actually changed, and always includes the explicit tag list when the title changes. Clearing `details` no longer clears `tags`; emptying the **Tags** field leaves the task without tags on purpose. Requires backend OpenAPI 1.3.0.
- **Writes are reflected immediately.** After a successful `POST`/`PATCH`/`DELETE`, the server response is merged into the local payload and cached, so the list updates without a new request and an offline refresh cannot roll back a successful save.

### Added
- **Status filters in TODO'S.** New **Pendientes / Terminadas / Todas** chips combine with the tag filter; **Pendientes** is active by default. Tag chips now show **Sin filtro** instead of a second “Todas”.
- **Tags field.** Adding or editing a task uses a three-field modal (Task, Tags, Details). Tags are optional, may be left empty, accept spaces or commas and an optional leading `#`.

### Changed
- The details icon is now an eye (`assets/icons/action/eye.svg`) instead of `notice-info`, and the add button is larger (its own thin `+` asset arrived in 2.13.1).
- Tag filter chips no longer show the book icon; a **long press** on a tag chip opens its Markdown (`/v1/todos/tags/<tag>.md`) with the current status filter.

## [2.12.1] - 2026-11-22

### Fixed
- **Refresh is back in TODO'S.** The `cre.render.reload` button now sits in the TASKS card header next to `+` and dispatches the existing `kh:refresh` flow. It had disappeared when the TASK LISTS card (which used to host it) was removed in 2.12.0.
- **Details can be created and edited.** Adding and editing a task now use a single `MultiInputDialog` with two fields (text/hashtags and a multiline details field), so notes can be supplied at creation time too. The **`notice-info`** and **`edit`** icons are shown on every row, including tasks without details; `notice-info` opens the full note in a text viewer.
- Replaced the unicode `✎`, `↗` and `i` glyphs (missing from the bundled Noto fonts) with KOReader's native SVG icons; the per-tag Markdown opener now uses `book.opened`.

## [2.12.0] - 2026-11-22

### Added
- **Tag filter chips in TODO'S.** The task list now has **Todas / #tag (n) / Sin etiqueta** chips that filter tasks locally over the cached index, with no extra requests. Each tag chip includes a **`↗`** glyph that opens the tag's Markdown (`/v1/todos/tags/<tag>.md`) in KOReader's native reader, re-downloaded on open because the Markdown is mutable.
- **Task `details`.** A new optional note (up to 1000 bytes, line breaks preserved) created and edited via `POST`/`PATCH`, shown as a two-line preview in the task row with an **`i`** glyph for the full text and a **`✎`** glyph to edit it. Indented details lines in Markdown are rendered inside their task item.

### Changed
- The Markdown **TASK LISTS** card and the `/todos/top` index are gone from the plugin; the same JSON index now drives the list, the filter and the CRUD. The backend endpoints remain available to other clients.
- **Show tag filters** replaces "Include tag lists" in TODO'S settings. Requires backend OpenAPI 1.2.0 for `details`; tasks without the field keep working.

## [2.11.0] - 2026-11-22

### Added
- **TODO'S is now a working tab.** Tapping it opens its own full-screen view with the same header and bottom navigation as the dashboard. It reads task lists from hnmd's `/todos/top?tags=true` (opened in KOReader's native reader, re-downloaded on every refresh because the Markdown is mutable) and tasks from `/todos?status=all`.
- **Task management.** Add a task with `#tags`, toggle done/undone, rename it, and delete it with confirmation. Writes use the existing `hnmd_api_key` through new `Http.post_json` / `Http.patch_json` / `Http.delete` helpers, with typed errors, a 64 KiB request cap and no automatic retry for `POST` or on `401`. Caches are invalidated after every write.
- Markdown task lists (`- [ ]` / `- [x]`) now render with a visible checkbox marker instead of literal brackets.

### Changed
- New settings under **TODO'S**: enable/disable, include per-tag lists and TTL (default 5 minutes). Writes require the server to allow them (`API_KEYS` or `TODO_ALLOW_INSECURE_WRITES`).
- Fixed a latent cache-first bug in `lib/refresh.lua`: a fresh cache entry was always treated as expired.

## [2.10.0] - 2026-11-21

### Added
- **Markdown images become safe links.** `![alt](url)` now renders as `<a href="url">alt</a>` in both `ReaderUI` and the fallback pager, so the image description stays visible and can be opened deliberately. Unsafe URLs (e.g. `javascript:`) degrade to plain alt text. No `<img>` is emitted and no network fetch is triggered automatically.

## [2.9.0] - 2026-11-21

### Added
- **Legacy `.md.html` migration.** On startup the plugin removes its old derived HTML files from the content folder (only files carrying the render marker are touched); the canonical `.md` is never deleted.

### Changed
- **Only Markdown is saved in the content folder.** Derived HTML is now rendered to `<DataDir>/cache/kindlehome/articles/` and deleted when the native reader or the fallback pager closes (and when a new article replaces it). KOReader still opens an HTML file in `ReaderUI`, so the render is regenerated on demand from the canonical `.md`; no `.html` is written next to the `.md` anymore.
- Existing local copies and link cards keep working: their HTML is recreated in the cache from the persisted Markdown.

## [2.8.0] - 2026-11-21

### Added
- **Configurable Top Stories rows per page.** New `hn_items_per_page` setting (1–10, default 4) under **Settings → Hacker News → Items per page**. The configured value is the preferred maximum; the dashboard still degrades rows to the largest count that fits before falling back to the native scroll container. Changing the setting resets Top Stories to page 1.

### Changed
- **Top Stories remembers its page for the session.** Closing and reopening the dashboard, returning from an article, and automatic refreshes keep the current page. Only an explicit refresh (the in-card reload button or the Dispatcher/gesture action) returns to page 1. The page is session-only: restarting KOReader or reloading the plugin starts again at page 1.
- **Page fitting uses a hybrid binary search.** The preferred row count is measured first (one build when it fits); if it overflows, a binary search finds the largest fitting size, bounding the work to `1 + ceil(log2(preferred))` builds instead of rebuilding once per row count.

## [2.7.0] - 2026-11-18

### Changed
- **Dashboard header is aligned to the content grid.** The title now starts at the same left margin as the cards and the settings/close icons end at the matching right margin; both icons are centered vertically in a fixed header band, with the hairline immediately above the body. New normalized `header/settings.svg` and `header/close.svg` assets give both glyphs the same viewBox, stroke weight and optical padding (native KOReader icons remain as fallback).
- **Top Stories fills the space it occupies, not the number of rows.** The card absorbs the leftover viewport height after the 4→3→2→1 fit decision, and the pager is pinned to its bottom edge. On the last page with fewer stories the arrows stay in exactly the same position; the spare space appears above them instead of pulling the pager upward.

## [2.6.0] - 2026-11-18

### Changed
- **Settings use KOReader's native full-screen menu again.** The gear now opens a `TouchMenu` at full screen width inside a `CenterContainer` with `covers_header = true` / `ignore = "height"` — the same pattern as KOReader's ReaderMenu. The custom floating card (`ModalPanel`, frame, 80% geometry and gesture re-offsetting) is gone. The native outside-tap handler, close arrow and Back key all dismiss the menu, and setting changes still repaint the dashboard only after it closes.

## [2.5.0] - 2026-11-18

### Changed
- **Settings open as a floating modal card.** The gear now shows a bordered white panel centered at 80% of the screen width, with the dashboard still visible around it. The panel grows with the current menu level up to a capped height, so submenus paginate inside the card. The native TouchMenu close arrow, the Back key and a tap outside the card all close it; setting changes still repaint the dashboard only after the modal closes.

## [2.4.1] - 2026-11-18

### Fixed
- **The gear opens the settings menu at full width.** `TouchMenu` expects each entry of `tab_item_table` to be the item array itself; 2.4.0 wrapped the sections in a nested `item_table`, so the tab had zero items and rendered as a tiny empty frame. The gear now passes the settings array directly as the single tab, carrying `text` and `icon` as extra fields.

## [2.4.0] - 2026-11-18

### Added
- **Previous-page control in Top Stories.** The pager now shows both arrows, wraps symmetrically in both directions, and is hidden when there is only one page. New monochrome `prev.svg` / `prev-inverse.svg` assets match the redesigned `next` glyph (plain paths, no SVG transforms).
- **Visible refresh feedback.** The hero shows `Updating…` (with the last update time when known) before the blocking network work starts, so the user sees that the dashboard is refreshing; the final state replaces it with the rebuilt data or the existing brief error hint.
- **Settings inside Kindle Home.** The dashboard gear now opens a single-tab native `TouchMenu` with the plugin settings (Weather, Hacker News, Sections, Interface, Refresh/network, Paths/storage). Setting changes repaint the dashboard on closing the menu, never over it.

### Fixed
- **Tools → Kindle Home opens the dashboard directly** instead of an intermediate submenu.
- **Pager and active-tab icons are visible again.** KOReader's `IconWidget` flattens icons onto white by default, which made the white `*-inverse.svg` glyphs disappear against the inverted black button/pressed tab; inverse icons now keep their alpha channel.

## [2.3.1] - 2026-11-16

### Fixed
- **Dashboard elements are no longer vertically centered.** The fit path used `LeftContainer` with the full viewport height, which centers its child vertically (`y + (dimen.h - content.h)/2`) and left the content floating with large blank areas. The content now lives in a top-aligned `HorizontalGroup` with a real left margin, followed by a `VerticalSpan` filler that pushes the fixed bottom tab bar down; pages with few stories start directly under the header.
- **No more scroll bar with offline/refresh notices.** `refresh_hint`, `weather.message` and `hn.message` could show the same connectivity status three times, adding enough height to trigger the scroll fallback. A global hint now suppresses redundant per-source notices, and section gaps/card padding were slightly reduced.

### Changed
- **Row count degrades before scrolling.** Top Stories still prefers 4 rows, but if the measured content does not fit the available height the dashboard rebuilds its model with 3 rows, then 2, then 1. A native `ScrollableContainer` is created only when even a single row cannot fit (very large `ui_font_scale` or landscape). Pagination and the next-page control use the chosen row count; the bottom tab bar stays fixed outside the scroll area.

## [2.3.0] - 2026-11-16

### Changed
- **Dashboard fits one screen.** Top Stories now shows **4 rows per page** instead of 5. The "Last refreshed" footer section is gone: a compact relative time (`2 min ago`) now sits to the left of the refresh button in the Top Stories header. The body is built without a scroll container when its measured height fits the available viewport; a native `ScrollableContainer` is created **only** as a fallback when the content cannot fit (very large `ui_font_scale` or landscape), with the bottom tab bar always fixed outside it.

### Fixed
- **Unwanted vertical scroll on the dashboard at normal scales.** Removing a whole story row and the footer section, and no longer adding a gap after the last section, brings the content within the available body height on Kindle at normal font scale.

## [2.2.0] - 2026-11-16

### Added
- **Paperwhite Monochrome dashboard.** Combined hero/weather card (clock with AM/PM, short date, last-update time, WiFi and battery glyph on the left; temperature, condition, H/L, place, wind, humidity and tomorrow on the right), separated by a hairline. Paginated **Top Stories** card with an inverted `Y/HN` badge, in-card refresh, five numbered rows and a `Page N of M` next-page control (wraps at the end; resets on refresh, preserved when returning from an article). Fixed three-tab bottom bar; **Dashboard** is active, **Todo's** and **Store** are placeholders with a brief “Coming soon” notice.
- **Custom dashboard header.** Literary serif title with settings and close buttons (settings opens the KOReader main menu, close keeps the existing exit path), wired to the Shell repaint target. Native `TitleBar`/action bar remain unchanged for the article fallback.
- **Monochrome SVG glyphs** for weather (sun/partly/cloud/fog/rain/snow/storm) and navigation, shipped under `assets/icons/`; sharp corners, discrete grays and binary inversion only.
- **12/24-hour clock** (`ui_clock_24h`, default `false` = 12 h with AM/PM) in the Interface menu.

### Changed
- **Weather payload extended** with current wind/humidity and a second forecast day (`forecast_days=2`, `wind_speed_unit=kmh`); additive, so older cache entries simply omit the new lines until their TTL expires. WMO codes now map to icon keys.
- Typography follows the design scale with KOReader's bundled **Noto Serif** (display/body) and **Noto Sans** (labels), with fallback to `cfont`; no fonts are bundled, keeping the plugin self-contained.
- Dashboard no longer uses the native action bar; refresh/close/settings live in the header and card as in the design.

### Fixed
- **Dashboard no longer fails to open.** `DashboardHeader` is now a real `InputContainer` widget (`getSize`/`paintTo`); previously it was a plain table and `Shell:init` crashed at `shell.lua:73` (`attempt to call method 'getSize'`). `Shell` also falls back to the native `TitleBar` if a custom header is not a valid widget.
- **No more KOReader crash on the first touch.** `BatteryGlyph` is now a `Widget` subclass; as a plain table it lacked `handleEvent()` and broke `WidgetContainer:propagateEvent` on any tap. The dashboard smoke now walks the whole widget tree asserting `handleEvent()` on every child (negative test reproduces the old crash).

## [2.1.0] - 2026-11-16

### Added
- **Custom content folder.** New `custom_content_dir` setting and **Choose custom content folder** entry under Paths and storage: an arbitrary absolute, nested path for downloaded documents (e.g. `/mnt/us/My Docs/KindleHome`). Relative paths, `..` segments and KOReader's install directory are rejected; an empty value restores `storage_mode`/`documents_subdir`. Paths are resolved only in `lib/paths.lua`; the cache stays in `<DataDir>`.
- **Native folder picker.** The folder is chosen with KOReader's `PathChooser` (directory-only mode, with folder creation and paginated navigation) instead of typing a path; **Reset custom content folder** restores the default location. Both share the existing validation/sanitization.

### Fixed
- **Elements bleeding through the title area.** The Shell now paints an opaque white full-screen background before drawing its children (`Shell:paintTo`), because `TitleBar` is a transparent `OverlapGroup` and `covers_fullscreen` prevents UIManager from repainting the previous screen. The `TitleBar` also receives `show_parent = self` as its repaint target. Closes use a `full` refresh.
- **Path visibility.** "Documents subdir" and "Storage mode" are marked *(fallback)* when a custom folder is active, and "Show resolved paths" became "Show active content paths".

### Changed
- **No file migration.** When the folder changes, already downloaded Markdown files, derived HTML and link cards stay in their previous location and are downloaded again when opened; they are neither copied nor deleted.

## [2.0.0] - 2026-11-16

### Removed
- **Digest (breaking change).** Removed `lib/digest.lua` and all integrations: dashboard card and button, `generate_digest`/`open_digest` actions, the `show_digest` setting, the `digest/` path, `ArticleStore` branches and documentation/smoke references. Already generated `digest/*.md` files on the device are **not deleted**.

### Added
- **Persistent link cards.** If a download fails and there is no local copy, `<id>-<slug>-links.md` (and its derived HTML) is written and opened with the HN URL, the source URL (or "Ask HN") and the failure reason. The card stays in the library even if a later download succeeds.
- **Real links in the document.** The document metadata includes `<a href>` links for the HN discussion and the source URL; tapping them in `ReaderUI` offers Copy / QR / Open in browser. Older renders are regenerated using a render schema marker.

### Fixed
- **Menu crash.** `prompt_text` no longer inserts a `nil` button into the `InputDialog` row (the cause of crashes when opening weather or "Documents subdir"). The API key Clear button now closes its dialog correctly.
- **Weather without a location.** `weather_lat`/`weather_lon` (default `nil`) can now be saved and reloaded from `settings/kindlehome.lua`; previously `Config:set` rejected them and weather never queried the API.

## [1.0.0] - 2026-11-16

### Changed
- **Release candidate.** Final release artifact; repository, gates and documentation ready for closeout.
- **Return from the native reader to the dashboard.** `Dashboard` keeps its shell alive beneath `ReaderUI` when an article opens in the reader; closing the reader returns to the dashboard instead of the file browser. The paginated fallback closes the dashboard as before; if `ReaderUI` fails to open, it is closed and the pager is shown (`on_fallback`).

### Fixed
- `ArticleView:show` now checks the return value of `openInReader`: a `ReaderUI:showReader` that silently fails (`false`) no longer prevents the pager fallback.

## [0.4.1] - 2026-11-16

### Changed
- **Native paginated article fallback.** `ui/article_html_pager.lua` replaces `ScrollHtmlWidget`: it uses a viewport-sized `HtmlBoxWidget`, `VerticalScrollBar` and native input (swipe, tap halves, **pan/release** and PgFwd/PgBack keys). Slow dragging now advances a page (it previously did nothing). The native `ReaderUI` remains the primary path.
- Removed `ScrollHtmlWidget` from the whole plugin; text selection in the fallback was dropped (it is available in `ReaderUI`).
- The error card/view never uses `kh:*` links in HTML; Back/Close navigation stays in the native bar.


## [0.4.0] - 2026-11-16

### Changed
- **Native dashboard UI.** The HTML body (`ScrollHtmlWidget` + CSS) was replaced by a KOReader widget tree (`TextBoxWidget`/`TextWidget`/`FrameContainer`/`LineWidget`) inside a `ScrollableContainer`: continuous pan scrolling and flick pagination with a native scrollbar. Clock/date, status, weather, HN and digest are built as widgets; tapping a headline uses the same `kh:hn:<id>` route.
- The digest card no longer contains an "Open latest digest" link: it only reports status; the Digest button in the native bar generates/opens the summary.
- Removed `lib/render/dashboard_html.lua` and `Theme.dashboard_css` (dead code).

### Added
- `lib/dashboard_model.lua`: pure view model (no KOReader dependencies) that normalizes `state` into sections/rows; allows verifying the dashboard in Lua 5.1 without widget stubs.
- `ui/dashboard_body.lua`: native body builder with computed widths to avoid horizontal scrolling and `LeftContainer` as the scroll container's only child.
- `Shell` registers `cropping_widget` when the body can crop (`ScrollableContainer`).

## [0.3.1] - 2026-11-16

### Fixed
- **Dashboard and article fallback did not scroll (they flashed without changing content).** `ScrollHtmlWidget` calls `UIManager:setDirty(self.dialog, ...)` when scrolling, but `UIManager` only marks widgets in `_window_stack` as dirty. `dialog` pointed at the nested body, so the e-ink refresh was queued but the next page was never painted. `Shell:init` now wires `body.dialog`, `body.show_parent` and `body.htmlbox_widget.dialog` to the `Shell`, which is the displayed widget. Self-assignments of `dialog = body/widget` were removed from `ui/dashboard.lua` and `ui/article_view.lua`.

### Added
- `Logger.info("shell", "layout", …)` with `screen_w/h`, `header`, `footer`, `body_h` and `fullscreen` (structured, no secrets) to confirm layout on device.

## [0.3.0] - 2026-11-16

### Changed
- **HN articles as downloaded Markdown files (hnmd contract).** `GET /v1/top` is used only as a metadata index (`schema_version`, `content_status`, `content_url`, `content_length`); tapping an item downloads `GET /v1/articles/{id}.md` to `<content root>/articles/hn/<id>-<slug>.md` and generates `<id>-<slug>.md.html` for `ReaderUI`.
- `hnmd_base_url` now defaults to `https://hnmd.miguehm.com/v1`; a host without a path gets `/v1` appended. `content_url` is resolved against the origin (avoiding `/v1/v1/...`) and cross-origin URLs are rejected.
- **Streaming download to file** (`Http.get_to_file`): the body is never accumulated in RAM (e-ink devices have very little free memory), with `index_max_bytes` (128 KiB) and `article_max_bytes` (512 KiB) limits, `Content-Length` validation and atomic `os.rename`.
- `Cache.SCHEMA_VERSION` bumped to 2: caches with the old full-payload format are quarantined and regenerated.
- Re-download only when the local `.md` is missing/empty; `404`, `503` or network failures **never** delete the local copy. No `etag`/`last-modified` used.
- Extended renderer: `h4`–`h6`, `blockquote`, `hr`, images reduced to alt text (no remote loads), plus `<!DOCTYPE html>` and `<title>` in persisted documents.
- Removed `open_in_reader_enabled`: the native reader is the default flow; the overlay remains as a fallback (raw Markdown if rendering fails).

### Added
- `lib/hnmd.lua`: `fetch_index` + `download_article` + `resolve_content_url` (schema/id/status validation).
- `lib/article_store.lua`: `ensure_local`, `is_local`, `render_derived` (regenerates HTML when the `.md` is newer) and own-frontmatter detection.
- `lib/paths.lua`: `article_md_path` / `article_html_path`.
- Typed errors `http_404` and `incomplete`; messages `no_content`, `warming_up`, `offline_no_local`, `downloading`.
- New smokes: `article_download.lua` (promotion/atomicity/404 keeps copy/clean `.tmp`), `md_render.lua` (extensions and escaping), `hnmd_url.lua` (`/v1` resolution, cross-origin, index/limits), `http_stream.lua` (chunked sink, `Content-Length`, `too_large`, no retry on 404/503, one retry on timeout).

## [0.2.1] - 2026-11-15

### Changed
- **Articles open in KOReader's native reader by default.** Articles and digests with a persisted local `.html` now open with `ReaderUI:showReader(path)` instead of the `ScrollHtmlWidget` overlay, enabling text selection, annotations, highlights, dictionary, progress and night mode, all offline.
- The `ScrollHtmlWidget` overlay remains only as a fallback when no local `.html` exists or the reader is unavailable; `highlight_text_selection = true` is enabled there.

## [0.2.0] - 2026-11-15

### Changed
- **UI redesigned for Kindle PaperWhite 5.** Absolute `font-size` CSS (px) replaced with relative `em` units; HTML base size now derives from KOReader's DPI-scaled `default_font_size`, so body text renders legibly on 300 ppi screens.
- **Hybrid native + HTML shell.** `ui/shell.lua` (`covers_fullscreen` + `TitleBar` + scrolling HTML body + `ui/widget/action_bar.lua`) replaces bare `ScrollHtmlWidget`. Full refresh (`setDirty(..., "full")`) at open/close to limit e-ink ghosting.
- **Always-visible exit paths:** TitleBar exit icon, footer "Exit" action, Back key, and swipe-down on the header.
- **Native action bar:** icon + short label per button (Refresh, Digest, Exit), targets ≥ ~58 dp, MDLight icons (no unreliable unicode glyphs in HTML).
- **Dashboard markup** (`lib/render/dashboard_html.lua`): hero clock/date, one Hacker News list (no duplicated "Actions"), full titles, relative times, weather/card/digest sections.
- **Article/digest overlay** on the same shell: Back (chevron.left), optional Reader, Close; navigation no longer at end of HTML.
- **Interface menu:** text size S/M/L/XL (`ui_font_scale`), fullscreen toggle, test-article link toggle.
- **Text sizes scale** with `ui_font_scale` for both HTML body and native buttons.

### Added
- `lib/render/theme.lua`: UI scale tokens, `covers_fullscreen`, em-only dashboard/article CSS.
- `lib/render/dashboard_html.lua`: dashboard body fragment builder.
- `ui/shell.lua`: fullscreen shell widget.
- `ui/widget/action_bar.lua`: native icon+label action bar.
- `scripts/smoke/shell.lua`, `scripts/smoke/action_bar.lua`: offline Lua 5.1 smoke tests.

## [0.1.2] - 2026-11-15

### Fixed
- **Blocking crash on first swipe/tap (device-confirmed).** `ScrollHtmlWidget` was created without `dialog`; its scroll handlers do `self.dialog.movable` (`frontend/ui/widget/scrollhtmlwidget.lua:182` on KOReader v2026.07), so any swipe/tap in the dashboard or article view raised `attempt to index field 'dialog' (a nil value)` and KOReader aborted. Both widgets now set `widget.dialog = widget` before `UIManager:show`.
- **Actions were never rendered.** `actions`/`title` are not `ScrollHtmlWidget` fields, so the dashboard showed text referring to buttons that could not exist. Actions are now real HTML links (`kh:refresh`, `kh:digest`, `kh:digest:latest`, `kh:hn:<id>`, `kh:test`, `kh:close`, and `kh:back`/`kh:dashboard`/`kh:reader` in articles) routed through `html_link_tapped_callback`.
- **Nested HTML documents.** Dashboard/article bodies are now passed as fragments with their stylesheet via the `css` option (`MdToHtml.document_body` added); persisted `.html` files still use the full document.
- **`Actions:dispatch` argument misuse.** Calls now use the `prefix:arg` form (`open_hn:<id>`, `open_digest:<date>`); the old extra arguments were silently ignored.
- Refresh failures are logged with the actual error instead of a bare `refresh_failed`.

### Changed
- `refresh_on_open` now defaults to **false**: opening always paints cached state and never blocks on HTTP; when enabled, the refresh is deferred with `UIManager:scheduleIn` after the first paint.
- `http_timeout_s` default 10 → 6 s and `http_max_bytes` 512 → 256 KiB (e-ink devices have very little free RAM).
- Content is written to the Kindle library (`/mnt/us/documents/KindleHome`) instead of inside the KOReader install dir (`getFullDataDir()` returns `/mnt/us/koreader` on Kindle).

### Added
- `scripts/check_invariants.sh`: static guards (ScrollHtmlWidget requires `dialog`; no nonexistent `ui/elements/menu_items`).

## [0.1.1] - 2026-11-15

### Fixed
- **Blocking: plugin failed to load on device.** `lib/paths.lua` used a Lua 5.3 bitwise XOR (`~`) in `short_hash`; KOReader on Kindle (Lua 5.1/LuaJIT) rejected `main.lua` with `unexpected symbol near '~'`, so `init()` never ran and the plugin was absent from all menus and from Plugin management. Replaced with a pure-arithmetic hash (no bitwise operators), safe on Lua 5.1.
- **Settings submenu never registered.** `ui/menus.lua` required the nonexistent `ui/elements/menu_items` module and registered the menu outside KOReader's official hook; `main.lua` silenced the failure with `pcall`. Now a single **Kindle Home** entry (Open dashboard + Weather, Hacker News, Sections, Refresh & network, Paths/storage) is registered through `addToMainMenu(menu_items)`.
- Removed `pcall` around menu registration and dead code in `main.lua`; removed deprecated `name` field from `_meta.lua`; release zip no longer contains empty `lib/rss/` directories.

### Added
- `scripts/check_lua51.sh`: mandatory Lua 5.1/LuaJIT syntax gate (`luac5.1`/`lua5.1`/`luajit`) for all plugin files, documented in `README.md` and `CONTRIBUTING.md`. A system `luac` 5.3+ is not a valid substitute.

## [0.1.0] - 2026-11-15

### Added
- Kindle Home KOReader plugin scaffold for Kindle (e-ink): dashboard, Dispatcher action `kindlehome_show_dashboard`, menus, and local device/time/battery/network status.
- Transversal base: config (`LuaSettings`), paths, cache (versioned envelope + recovery), HTTP client (timeouts/limits/typed errors), refresh coordinator (cache-first, budget/reentry), structured logger.
- Reading pipeline: Markdown-to-HTML rendering, article persistence (`.md/.html`, atomic writes), overlay article view, and internal Lua action routing.
- Weather integration (Open-Meteo + geocoding/WMO), HN via `hnmd` (`/top`) with auth/cache/error handling, and daily digest generation/opening.

### Changed
- Scope narrowed to Hacker News via `hnmd` only (RSS/Atom removed).
- Settings/refresh/UI hardening: centralized brief user messages, configurable toggles/TTLs/limits, WiFi prompt/fallback, and sequential budgeted refresh.

### Security
- `hnmd_api_key` treated as local plaintext KOReader setting; masked in UI, never logged. HTTP/auth/payload details not logged.
- Cache/content writes are atomic; corrupted/incompatible cache is quarantined/regenerated.

### Deferred
- Alternative HN fallback, full i18n, screensaver/userpatch integration.
- External URL fetch/open in an overlay.
