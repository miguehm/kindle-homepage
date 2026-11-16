# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, weather (Open-Meteo), and Hacker News via `hnmd`.

- **Version:** 0.1.2 (MVP)
- **Content scope:** Hacker News via `hnmd` only (`https://hnmd.miguehm.com/top` by default). RSS/Atom and external URL fetch (5.10) are not supported in MVP.

## Status

Phases 0–7 are implemented in repo (dashboard/offline state, transversal base, reading/persistence, weather, HN/hnmd, digest, settings/Dispatcher/refresh policy/messages/limits). Phase 8 repo prep (8.1–8.5: static checks, docs, version bump, release zip) is done; **0.1.1 fixed the Lua 5.3 syntax crash (`lib/paths.lua`) and the never-registered settings submenu, and 0.1.2 fixed the device crash on first swipe/tap (`ScrollHtmlWidget` without `dialog`)** plus real action links, no blocking refresh on open, and content stored in the Kindle library. **F1–F8 runtime verification and ledger closure on Kindle (KOReader) are still pending device execution** — see `PLAN.md` §7, §9, §10.

## Installation (Kindle — target)

1. Copy or extract `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open **Tools → Kindle Home** (with the default `sorting_hint`) or assign the **Kindle Home** Dispatcher action (`kindlehome_show_dashboard`) to a gesture/Profile. If the entry does not appear, see Troubleshooting.

### Install from release zip
- Use a release zip that contains the `kindlehome.koplugin/` directory (e.g. `kindlehome.koplugin-v0.1.2.zip`). Extract/copy that folder into `/mnt/us/koreader/plugins/`, then restart KOReader.

## Development (auxiliary only)

KOReader on Linux desktop may be used for quick iteration (not a supported target): copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader. Final behavior/UX validation is on **Kindle real**.

**Required gates before committing/releasing:** `./scripts/check_lua51.sh` (Lua 5.1/LuaJIT syntax), `./scripts/check_invariants.sh` (e.g. every `ScrollHtmlWidget:new` must set `dialog`) and `./scripts/smoke_ui.sh` (offline render + link wiring). KOReader on Kindle runs Lua 5.1/LuaJIT; Lua 5.3+ bitwise/integer syntax (e.g. `~`, `//`) crashes plugin loading, while a system `luac` 5.3+ accepts it silently.

## Configuration

- **Settings file:** `<KOReader settings dir>/kindlehome.lua` (`LuaSettings`, i.e. `DataStorage:getSettingsDir()/kindlehome.lua`; defaults/sanitization in `lib/config.lua`). Out-of-range/invalid values fall back to defaults.
- **In-app menu:** a single **Kindle Home** entry in the main menu (under Tools) whose submenu has **Open dashboard** plus the settings sections: Weather, Hacker News, Sections, Refresh & network, Paths/storage. You can also edit `settings/kindlehome.lua` manually while KOReader is not running.

### Hacker News (`hnmd`)
- `hnmd_enabled`, `show_hn`
- `hnmd_base_url` (default `https://hnmd.miguehm.com`, sanitized to https)
- `hnmd_api_key` (Bearer token) — set via UI or edit `hnmd_api_key = "..."` in `kindlehome.koplugin` settings file
- `hnmd_max_items` (1–20), `hnmd_ttl_minutes`

Behavior: cache-first with stale fallback. `401` is actionable and never auto-retried. `503 warming_up`, offline/network/timeout/parse/too_large fall back to cached HN when available. Articles with `status==ok` and markdown are rendered/persisted as `.md/.html` under `articles/hn/`. Ask HN (`url == null`) uses hnmd content only.

### Weather (Open-Meteo)
- `weather_enabled`, `show_weather`, location search or `weather_lat`/`weather_lon`, `weather_place_name`, `weather_ttl_minutes`
- Cache-first fetch; offline/TTL handling with stale fallback and WiFi prompt/fallback when refreshing.

### Refresh, limits and paths
- `refresh_on_open`, `refresh_budget_s`, `http_timeout_s`, `http_max_bytes` (enforced; sequential per-source, reentry-guarded)
- `storage_mode` (`documents|datadir`), `documents_subdir` (default `KindleHome`)
- `open_in_reader_enabled` (bool, default `false`, manual config only): enable isolated “Open in reader” for generated HTML when available
- Cache: `<DataDir>/cache/kindlehome/*.json` (versioned envelope; corrupt/incompatible cache quarantined/regenerated)
- Content root:
  - `storage_mode = "documents"` (default): `<documents root>/<documents_subdir>` — on Kindle `/mnt/us/documents/KindleHome` (resolved from `home_dir` + `documents`, so content shows up in the device library)
  - `storage_mode = "datadir"`: `<DataDir>/news/kindlehome`
  - HN articles: `<content root>/articles/hn/`; digests: `<content root>/digest/`

## Usage

- Dashboard shows date/time, device status, weather, HN, and digest sections (toggleable).
- **Actions:** tap the links at the bottom of the dashboard (`Refresh`, `Generate digest`, `Open latest digest`, `Open test article`, `HN <rank>: <title>`, `Close`). KOReader's `ScrollHtmlWidget` has no buttons; links are routed through `html_link_tapped_callback`.
- **Refresh:** manual by default (`refresh_on_open = false` in this MVP). When enabled it paints cached state first and refreshes right after, cache-first and conditioned by connectivity/TTL/budget; brief progress/status messages, no stack traces.
- **Dispatcher:** `kindlehome_show_dashboard` (safe/idempotent) for gestures/Profiles.
- **Reading:** overlay view from persisted/rendered content; internal Lua actions for open/return. “Open in reader” is behind `open_in_reader_enabled` (default off, manual config) and isolated.
- **Digest:** generate/open latest or by date from cached dashboard state (partial data supported).

## Security and privacy

- `hnmd_api_key` and authorization headers are **never logged**; API key is stored locally in plaintext by KOReader settings and masked in UI.
- HTTP requests go through `lib/http.lua` with timeout/size limits and typed errors.
- Cache/content persistence uses atomic writes and canonical paths.

## Troubleshooting

- **401 (HN):** verify API key in Settings or `settings/kindlehome.lua`; restart refresh. No automatic retry on 401.
- **503 warming_up / offline / timeout / network / parse / too_large:** plugin keeps/uses cached data when available and shows brief status; retry when network/service is ready.
- **No location/weather:** configure place or lat/lon in Settings.
- **No HN markdown / Ask HN:** item may have no renderable markdown; Ask HN uses hnmd content only (no external fetch).
- **Corrupted cache:** removed/quarantined automatically and regenerated on next fetch.
- **Plugin not visible:** ensure the folder is `kindlehome.koplugin` directly under `/mnt/us/koreader/plugins/` (not nested) and **restart KOReader**. Then check `crash.log` for `WARN Error when loading plugins/kindlehome.koplugin/main.lua`:
  - `unexpected symbol near '~'` (or `//`, `goto`) ⇒ Lua 5.1 incompatibility; run `./scripts/check_lua51.sh` in the repo and reinstall.
  - Any load error means `init()` never ran: no `cache/kindlehome`, no menu entry, nothing in **Plugin management → User plugins**. Fix the error and reinstall rather than only restarting.
- **Entry exists but dashboard/settings missing:** verify the plugin version is 0.1.2+.
- **KOReader closes right after opening the dashboard:** fixed in 0.1.2 (`ScrollHtmlWidget` without `dialog` → `attempt to index field 'dialog'` on swipe/tap). Update the plugin; if it reappears, run `./scripts/check_invariants.sh`.
- **Performance on e-ink:** reduce `hnmd_max_items`, increase TTLs, or adjust `refresh_budget_s`/timeouts within sane limits.

## Release checklist (8.5)

- [x] `./scripts/check_lua51.sh`, `./scripts/check_invariants.sh` and `./scripts/smoke_ui.sh` pass (syntax, structural invariants, offline UI rendering)
- [ ] 8.1 matrix executed on **Kindle (KOReader)** and recorded in `PLAN.md` §10 (or blocking issues documented)
- [ ] 8.2 performance observations/defaults reviewed on Kindle; 8.3 runtime security/privacy validation on Kindle
- [x] `README.md`, `CHANGELOG.md`, `PLAN.md` updated; `_meta.lua` version bumped (repo prep)
- [x] Zip contains only `kindlehome.koplugin/` (no `.git`, no local artifacts, no empty dirs), verified via listing; **clean Kindle install from zip pending device run**

## Deferred / out of scope (MVP)

- Fallback HN alternative, full i18n, screensaver/userpatch (8.6, deferred post-MVP)
- External URL fetch/open in overlay (5.10)
