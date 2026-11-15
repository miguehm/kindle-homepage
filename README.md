# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, weather (Open-Meteo), and Hacker News via `hnmd`.

- **Version:** 0.1.0 (MVP)
- **Content scope:** Hacker News via `hnmd` only (`https://hnmd.miguehm.com/top` by default). RSS/Atom and external URL fetch (5.10) are not supported in MVP.

## Status

Phases 0–7 are implemented in repo (dashboard/offline state, transversal base, reading/persistence, weather, HN/hnmd, digest, settings/Dispatcher/refresh policy/messages/limits). Phase 8 repo prep (8.1–8.5: static checks, docs, version bump, release zip) is done, but **F1–F8 runtime verification and ledger closure on Kindle (KOReader) are pending device execution** — see `PLAN.md` §7, §9, §10.

## Installation (Kindle — target)

1. Copy or extract `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open **Kindle Home** from the KOReader main menu, or assign the **Kindle Home** Dispatcher action (`kindlehome_show_dashboard`) to a gesture/Profile.

### Install from release zip
- Use a release zip that contains the `kindlehome.koplugin/` directory (e.g. `kindlehome.koplugin-v0.1.0.zip`). Extract/copy that folder into `/mnt/us/koreader/plugins/`, then restart KOReader.

## Development (auxiliary only)

KOReader on Linux desktop may be used for quick iteration (not a supported target): copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader. Final behavior/UX validation is on **Kindle real**.

## Configuration

- **Settings file:** `<KOReader settings dir>/kindlehome.lua` (`LuaSettings`, i.e. `DataStorage:getSettingsDir()/kindlehome.lua`; defaults/sanitization in `lib/config.lua`). Out-of-range/invalid values fall back to defaults.
- **In-app menu:** **Kindle Home** settings entry (registered in KOReader main menu; sections: Weather, Hacker News, Sections, Refresh & network, Paths/storage). You can also edit `settings/kindlehome.lua` manually while KOReader is not running.

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
  - `storage_mode = "documents"` (default): `<KOReader data/home dir>/\<documents_subdir>` (resolved via `DataStorage:getFullDataDir()`, fallback `<DataDir>/documents/<documents_subdir>`)
  - `storage_mode = "datadir"`: `<DataDir>/news/kindlehome`
  - HN articles: `<content root>/articles/hn/`; digests: `<content root>/digest/`

## Usage

- Dashboard shows date/time, device status, weather, HN, and digest sections (toggleable).
- **Refresh:** manual or on open (cache-first, conditioned by connectivity/TTL/budget). Brief progress/status messages; no stack traces.
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
- **Plugin not visible:** ensure folder is `kindlehome.koplugin` under KOReader plugins path and **restart KOReader**.
- **Performance on e-ink:** reduce `hnmd_max_items`, increase TTLs, or adjust `refresh_budget_s`/timeouts within sane limits.

## Release checklist (8.5)

- [x] `luac -p` passes for all `kindlehome.koplugin/**/*.lua` (repo static check)
- [ ] 8.1 matrix executed on **Kindle (KOReader)** and recorded in `PLAN.md` §10 (or blocking issues documented)
- [ ] 8.2 performance observations/defaults reviewed on Kindle; 8.3 runtime security/privacy validation on Kindle
- [x] `README.md`, `CHANGELOG.md`, `PLAN.md` updated; `_meta.lua` version bumped (repo prep)
- [x] Zip contains only `kindlehome.koplugin/` (no `.git`, no local artifacts), verified via listing; **clean Kindle install from zip pending**

## Deferred / out of scope (MVP)

- Fallback HN alternative, full i18n, screensaver/userpatch (8.6, deferred post-MVP)
- External URL fetch/open in overlay (5.10)
