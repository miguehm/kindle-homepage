# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, weather (Open-Meteo), and Hacker News via `hnmd`.

- **Version:** 2.3.1
- **Content scope:** Hacker News via `hnmd` only (`https://hnmd.miguehm.com/v1` by default). Article bodies are downloaded as Markdown files (`/v1/articles/{id}.md`); RSS/Atom and external URL fetch (5.10) are not supported in MVP.

## Status

Phases 0–13 are implemented in repo; the MVP was formally closed as 1.0.0 after the full matrix PASSed on Kindle PW5 (2026-11-16; see `PLAN.md` §7/§10). **Release 2.0.0** adds the post-MVP mitigations from `REVIEW.md`: the digest feature is gone (breaking release), weather coordinates are now really saved/loaded, the menu crashes are fixed, failed downloads open a persistent link card with the source URLs, and HN/source URLs render as real links inside the document. The dashboard still uses native KOReader widgets with a `ScrollableContainer` (pan/flick/scrollbar) and the article fallback uses a native paginated HTML pager — no `ScrollHtmlWidget` remains. HN articles are streamed to `.md` (never buffered in RAM) with a derived `.md.html` opened by KOReader's native reader; returning from `ReaderUI` lands back on the dashboard. Release 2.0.0 was verified on Kindle PW5 (2026-11-16; see `PLAN.md` §10). **Release 2.1.0** fixes the title-area bleed-through (the Shell now paints an opaque full-screen background before the native `TitleBar`) and adds a **custom content folder** for an arbitrary absolute/nested downloads directory, chosen with KOReader's native folder picker (plus a **Reset** entry); existing downloads are not migrated (they are re-downloaded when opened).

**Release 2.2.0** refactors the dashboard to the **Paperwhite Monochrome** design (`DESIGN.md`, `dashboard.png`): a single hero/weather card, a paginated **Top Stories** card with an in-card refresh and next-page button, a fixed bottom tab bar (**Dashboard**, **Todo's**, **Store** — the last two are placeholders), a custom header with settings and close, and monochrome SVG glyphs. Typography uses KOReader's bundled Noto Serif/Noto Sans (Literata/Inter are not available on device). Weather now shows wind, humidity and tomorrow's high/low; the hero clock defaults to 12 h with AM/PM (`ui_clock_24h` restores 24 h).

**Release 2.3.0** makes the dashboard fit one screen: **Top Stories shows 4 rows per page**, the compact refresh time (`2 min ago`) moved into the stories header next to the refresh button, and the old "Last refreshed" footer section is gone. The body is built without a scroll container when the measured content fits; a native `ScrollableContainer` is used **only** as a fallback for extreme font scales or landscape, with the bottom tab bar always fixed. **Release 2.3.1** anchors the content to the top-left (no more vertical centering or missing left margin), suppresses duplicated offline/refresh notices, and degrades the story rows from 4 to 3 (then 2 and 1) when the measured content would otherwise overflow: the scroll bar is now a last resort for extreme scales/landscape only.

## Installation (Kindle — target)

1. Copy or extract `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open **Tools → Kindle Home** (with the default `sorting_hint`) or assign the **Kindle Home** Dispatcher action (`kindlehome_show_dashboard`) to a gesture/Profile. If the entry does not appear, see Troubleshooting.

### Install from release zip
- Use a release zip that contains the `kindlehome.koplugin/` directory (e.g. `kindlehome.koplugin-v2.1.0.zip`). Extract/copy that folder into `/mnt/us/koreader/plugins/`, then restart KOReader.

## Development (auxiliary only)

KOReader on Linux desktop may be used for quick iteration (not a supported target): copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader. Final behavior/UX validation is on **Kindle real**.

**Required gates before committing/releasing:** `./scripts/check_lua51.sh` (Lua 5.1/LuaJIT syntax), `./scripts/check_invariants.sh` (measured dashboard scroll fallback, native article pager, top-level repaint target, menu registration, streamed downloads) and `./scripts/smoke_ui.sh` (offline model/widget rendering, fit and fallback paths, action wiring). KOReader on Kindle runs Lua 5.1/LuaJIT; Lua 5.3+ bitwise/integer syntax (e.g. `~`, `//`) crashes plugin loading, while a system `luac` 5.3+ accepts it silently.

## Configuration

- **Interface:** `ui_font_scale` (S–XL), `ui_clock_24h` (12/24 h), `ui_fullscreen`; the custom header exposes **settings** (opens the KOReader menu) and **close**.
- **Settings file:** `<KOReader settings dir>/kindlehome.lua` (`LuaSettings`, i.e. `DataStorage:getSettingsDir()/kindlehome.lua`; defaults/sanitization in `lib/config.lua`). Out-of-range/invalid values fall back to defaults.
- **In-app menu:** a single **Kindle Home** entry in the main menu (under Tools) whose submenu has **Open dashboard** plus the settings sections: Weather, Hacker News, Sections, Refresh & network, Paths/storage. You can also edit `settings/kindlehome.lua` manually while KOReader is not running.

### Hacker News (`hnmd`)
- `hnmd_enabled`, `show_hn`
- `hnmd_base_url` (default `https://hnmd.miguehm.com/v1`, sanitized to https; a bare host gets `/v1` appended)
- `hnmd_api_key` (Bearer token) — set via UI or edit `hnmd_api_key = "..."` in `kindlehome.koplugin` settings file
- `hnmd_max_items` (1–20), `hnmd_ttl_minutes`, `index_max_bytes` (32–256 KiB, default 128 KiB), `article_max_bytes` (16 KiB–1 MiB, default 512 KiB)

Behavior: `GET /v1/top` returns index metadata only (cache-first with stale fallback; `401` actionable and never auto-retried; `503 warming_up`, offline/network/timeout/parse/too_large fall back to cached HN when available). Tapping an item resolves `content_url` (origin-absolute `/v1/articles/{id}.md`), streams the Markdown to `<content root>/articles/hn/<id>-<slug>.md` and writes a derived `<id>-<slug>.md.html` for `ReaderUI`. A local copy is only re-downloaded when missing/empty; `404` and network errors never delete it. If the article cannot be downloaded and there is no local copy, the plugin writes and opens `<id>-<slug>-links.md` / `.md.html`: a small link card with the HN discussion URL, the source URL (or “Ask HN”), and the failure reason. The card stays in the library even after a later successful download. Ask HN (`url == null`) uses hnmd content only.

### Weather (Open-Meteo)
- `weather_enabled`, `show_weather`, location search or `weather_lat`/`weather_lon`, `weather_place_name`, `weather_ttl_minutes`. The request also fetches current wind/humidity and a second forecast day (tomorrow); missing fields simply hide their line.
- Cache-first fetch; offline/TTL handling with stale fallback and WiFi prompt/fallback when refreshing.

### Refresh, limits and paths
- `refresh_on_open`, `refresh_budget_s`, `http_timeout_s`, `http_max_bytes` (weather/menus), `index_max_bytes`/`article_max_bytes` (downloads; enforced while streaming; sequential per-source, reentry-guarded)
- `storage_mode` (`documents|datadir`), `documents_subdir` (default `KindleHome`), `custom_content_dir` (default empty = disabled)
- Cache: `<DataDir>/cache/kindlehome/*.json` (versioned envelope; corrupt/incompatible cache quarantined/regenerated) — never moves with the content root
- Content root (in precedence order):
  - `custom_content_dir` (set via **Paths and storage → Choose custom content folder**, which opens KOReader's native folder picker): an absolute, normalized path such as `/mnt/us/My Docs/KindleHome`; nested paths are allowed, but relative paths, `..` segments and KOReader's own install directory (`/mnt/us/koreader`) are rejected. **Reset custom content folder** clears it and restores the options below. On Kindle touch devices, long-press a folder name to select it (or use the first “choose current folder” row); the picker also has a **New folder** action via long-press on its home icon. Existing downloads are **not** migrated: they stay in their old folder and are re-downloaded when opened.
  - `storage_mode = "documents"` (default): `<documents root>/<documents_subdir>` — on Kindle `/mnt/us/documents/KindleHome` (resolved from `home_dir` + `documents`, so content shows up in the device library)
  - `storage_mode = "datadir"`: `<DataDir>/news/kindlehome`
  - HN articles: `<content root>/articles/hn/` (canonical `<id>-<slug>.md`, derived `<id>-<slug>.md.html`, and persistent fallback `<id>-<slug>-links.md/.html`)

## Usage

- Dashboard shows a combined date/time + weather card, device status, and a paginated HN **Top Stories** list (toggleable sections).
- **Dashboard:** the body uses native KOReader widgets laid out to fit the available height; a native `ScrollableContainer` is created only when the measured content cannot fit (e.g. very large `ui_font_scale` or landscape). The bottom tab bar is always fixed. Tap a headline to open it; the compact refresh time sits to the left of the refresh button in the Top Stories header, and the close/settings buttons are in the custom header. The next-page button cycles through 4-story pages and returns to page 1 on refresh; page state survives returning from an article. The test-article row appears only when `ui_show_test_article = true`.
- **Refresh:** manual by default (`refresh_on_open = false` in this MVP). When enabled it paints cached state first and refreshes right after, cache-first and conditioned by connectivity/TTL/budget; brief progress/status messages, no stack traces.
- **Dispatcher:** `kindlehome_show_dashboard` (safe/idempotent) for gestures/Profiles.
- **Reading:** tapping an HN item ensures `<id>-<slug>.md` exists (downloads it on first tap), regenerates `<id>-<slug>.md.html` when the Markdown is newer *or when the derived HTML predates the link-meta format*, and opens it in KOReader's native reader (`ReaderUI`): text selection, annotations, progress, dictionary and night mode, all offline. HN and source URLs appear as real links in the document metadata; tapping one in `ReaderUI` offers Copy / QR / Open in browser. Exiting the reader returns to the dashboard. If the reader is unavailable or rendering fails, the in-plugin fallback uses a native paginated HTML pager (swipe, tap, pan and PgFwd/PgBack).

## Security and privacy

- `hnmd_api_key` and authorization headers are **never logged**; API key is stored locally in plaintext by KOReader settings and masked in UI.
- HTTP requests go through `lib/http.lua` with timeout/size limits and typed errors.
- Cache/content persistence uses atomic writes and canonical paths.

## Troubleshooting

- **401 (HN):** verify API key in Settings or `settings/kindlehome.lua`; restart refresh. No automatic retry on 401.
- **503 warming_up / offline / timeout / network / parse / too_large:** plugin keeps/uses cached data when available and shows brief status; retry when network/service is ready.
- **No location/weather:** configure place or lat/lon in Settings.
- **No article content (`no_content`/`warming_up`):** hnmd has not extracted that item yet; the plugin opens a persistent link card with the available URLs, and you can retry later. **`http_404`:** the server has no body for that id (a local copy is kept if present; otherwise a link card opens). **`incomplete`:** length mismatch while downloading; retry. Ask HN uses hnmd content only (no external fetch).
- **Corrupted cache:** removed/quarantined automatically and regenerated on next fetch.
- **Plugin not visible:** ensure the folder is `kindlehome.koplugin` directly under `/mnt/us/koreader/plugins/` (not nested) and **restart KOReader**. Then check `crash.log` for `WARN Error when loading plugins/kindlehome.koplugin/main.lua`:
  - `unexpected symbol near '~'` (or `//`, `goto`) ⇒ Lua 5.1 incompatibility; run `./scripts/check_lua51.sh` in the repo and reinstall.
  - Any load error means `init()` never ran: no `cache/kindlehome`, no menu entry, nothing in **Plugin management → User plugins**. Fix the error and reinstall rather than only restarting.
- **Entry exists but dashboard/settings missing:** verify the plugin version is 0.4.1+.
- **KOReader closes right after opening the dashboard:** fixed in 0.1.2; scrolling without repaint fixed in 0.3.1 (`Shell` must be the `dialog`/`show_parent` of the body). Update the plugin; if it reappears, run `./scripts/check_invariants.sh`.
- **Performance on e-ink:** reduce `hnmd_max_items`, increase TTLs, or adjust `refresh_budget_s`/timeouts within sane limits.

## Release checklist (8.5)

- [x] `./scripts/check_lua51.sh`, `./scripts/check_invariants.sh` and `./scripts/smoke_ui.sh` pass (syntax, structural invariants, offline UI rendering)
- [x] 8.1 matrix executed on **Kindle (KOReader)** and recorded in `PLAN.md` §10 (PASS 2026-11-16; no blocking issues)
- [x] 8.2 performance observations/defaults reviewed on Kindle; 8.3 runtime security/privacy validation on Kindle (PASS 2026-11-16)
- [x] `README.md`, `CHANGELOG.md`, `PLAN.md` updated; `_meta.lua` version bumped to 1.0.0 (repo prep, F13)
- [x] Zip contains only `kindlehome.koplugin/` (no `.git`, no local artifacts, no empty dirs), verified via listing; **clean Kindle install from zip verified on device (PASS 2026-11-16)**
- [x] Fase 15 (2.1.0): opaque full-screen Shell background + custom content folder; `_meta.lua` bumped to 2.1.0, gates and 15 smokes PASS. **Kindle PW5 matrix PASS for F15.1–F15.3 (confirmed 2026-11-16).** F15.4 (native folder picker + Reset) repo PASS, pending device verification (see `PLAN.md` §10).

## Deferred / out of scope (MVP)

- Fallback HN alternative, full i18n, screensaver/userpatch (8.6, deferred post-MVP)
- External URL fetch/open in overlay (5.10)
