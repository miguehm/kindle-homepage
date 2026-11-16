# Changelog

## [0.1.2] - 2026-11-15

### Fixed
- **Blocking crash on first swipe/tap (device-confirmed).** `ScrollHtmlWidget` was created without `dialog`; its scroll handlers do `self.dialog.movable` (`frontend/ui/widget/scrollhtmlwidget.lua:182` on KOReader v2026.07), so any swipe/tap in the dashboard or article view raised `attempt to index field 'dialog' (a nil value)` and KOReader aborted. Both widgets now set `widget.dialog = widget` before `UIManager:show`.
- **Actions were never rendered.** `actions`/`title` are not `ScrollHtmlWidget` fields, so the dashboard showed text referring to buttons that could not exist. Actions are now real HTML links (`kh:refresh`, `kh:digest`, `kh:digest:latest`, `kh:hn:<id>`, `kh:test`, `kh:close`, and `kh:back`/`kh:dashboard`/`kh:reader` in articles) routed through `html_link_tapped_callback`.
- **Nested HTML documents.** Dashboard/article bodies are now passed as fragments with their stylesheet via the `css` option (`MdToHtml.document_body` added); persisted `.html` files still use the full document.
- **`Actions:dispatch` argument misuse.** Calls now use the `prefix:arg` form (`open_hn:<id>`, `open_digest:<date>`); the old extra arguments were silently ignored.
- Refresh failures are logged with the actual error instead of a bare `refresh_failed`.

### Changed
- `refresh_on_open` now defaults to **false** (MVP): opening always paints cached state and never blocks on HTTP; when enabled, the refresh is deferred with `UIManager:scheduleIn` after the first paint.
- `http_timeout_s` default 10 → 6 s and `http_max_bytes` 512 → 256 KiB (device had ~15 MB free RAM).
- Content is written to the Kindle library (`/mnt/us/documents/KindleHome`) instead of inside the KOReader install dir (`getFullDataDir()` returns `/mnt/us/koreader` on Kindle).

### Added
- `scripts/check_invariants.sh`: static guards (ScrollHtmlWidget requires `dialog`; no nonexistent `ui/elements/menu_items`).

### Verification
- Device: KOReader v2026.07 / LuaJIT 2.1.1783773675, Kindle PaperWhite 5. Evidence in `PLAN.md` §9/§10 (3 tracebacks at `scrollhtmlwidget.lua:182` after `[KindleHome] event=shown`).
- Repo: `check_lua51.sh` PASS (22 files), `check_invariants.sh` PASS (and negative test fails as expected). **Interactive re-test on device (scroll/tap in all directions, HN article, digest) pending.**

## [0.1.1] - 2026-11-15

### Fixed
- **Blocking: plugin failed to load on device.** `lib/paths.lua` used a Lua 5.3 bitwise XOR (`~`) in `short_hash`; KOReader on Kindle (Lua 5.1/LuaJIT) rejected `main.lua` with `unexpected symbol near '~'`, so `init()` never ran and the plugin was absent from all menus and from Plugin management. Replaced with a pure-arithmetic hash (no bitwise operators), safe on Lua 5.1.
- **Settings submenu never registered.** `ui/menus.lua` required the nonexistent `ui/elements/menu_items` module and registered the menu outside KOReader's official hook; `main.lua` silenced the failure with `pcall`. Now a single **Kindle Home** entry (Open dashboard + Weather, Hacker News, Sections, Refresh & network, Paths/storage) is registered through `addToMainMenu(menu_items)`.
- Removed `pcall` around menu registration and dead code in `main.lua`; removed deprecated `name` field from `_meta.lua`; release zip no longer contains empty `lib/rss/` directories.

### Added
- `scripts/check_lua51.sh`: mandatory Lua 5.1/LuaJIT syntax gate (`luac5.1`/`lua5.1`/`luajit`) for all plugin files, documented in `AGENTS.md` and `README.md`. A system `luac` 5.3+ is not a valid substitute.

### Verification
- Repo (2026-11-15, Linux dev): `luac5.1 -p` PASS for all 22 `kindlehome.koplugin/**/*.lua`; before the fix it reproduced the device error at `lib/paths.lua:55`. Negative test confirmed the gate fails on synthetic Lua 5.3 bitwise syntax.
- Device evidence (v0.1.0 failure) and the gate run are recorded in `PLAN.md` §9/§10. **Reinstall 0.1.1 on Kindle and confirm the plugin loads (no `WARN Error when loading` in `crash.log`) remains pending.**

## [0.1.0] - 2026-11-15 (MVP)

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

### Verification
- Repo/static (2026-11-15, Linux dev): `luac -p` passed for all `kindlehome.koplugin/**/*.lua` (**superseded**: the system `luac` was 5.5, not Lua 5.1/LuaJIT — see 0.1.1); logger/HTTP/UI audit showed no API key, Authorization header, or payload logging.
- **Kindle (KOReader) runtime/device validation:** required for MVP closure (F1–F8 matrix: offline/unstable WiFi, 401/503/parse/too_large, geocoding/TTL, cache corruption, digest/reading, Dispatcher/Profiles/gestures, performance). Not executed in this environment; record results in `PLAN.md` §10.

### Deferred (post-MVP)
- 8.6: alternative HN fallback, full i18n, screensaver/userpatch.
- 5.10: external URL fetch/open in overlay.
