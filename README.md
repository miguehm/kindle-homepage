# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, and (planned) weather and Hacker News via `hnmd` (`https://hnmd.miguehm.com/top`).

## Status

Phase 1 (offline dashboard) and Phase 2 (transversal base) implemented in code; **Phase 3 reading base (renderer, article overlay, persistence, internal action routing) and Phase 4 weather base (WMO, geocoding, Open-Meteo fetch, cache-first/stale fallback, dashboard section, minimal settings) implemented in repo**. **F1 device verification on Kindle, F2 verification ledger, and F3/F4 runtime verification remain pending**. UI language: English. RSS/Atom support removed from scope (HN-only via `hnmd`).

## Installation (Kindle — target)

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu (and later via Dispatcher/gestures).

## Development (optional, auxiliary)

KOReader on Linux desktop may be used only for quick iteration (not a supported target). Copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader.

## Notes

- Current build: local dashboard with date/time, battery/network status, and weather section (current + min/max, WMO text, stale/cache state, configure-location prompt); refresh is cache-first with reentry guard and WiFi prompt/fallback when user-initiated offline.
- Transversal modules: `lib/config.lua` (defaults/validation), `lib/paths.lua` (canonical paths, atomic writes helper), `lib/cache.lua` (versioned envelope, quarantine/recovery), `lib/http.lua` (timeouts/limits/typed errors), `lib/refresh.lua` (cache-first/stale/budget/reentry guard), `lib/logger.lua`.
- Reading base (Phase 3): `lib/render/md_to_html.lua` (MD basic → safe HTML + e-ink CSS), `lib/article_store.lua` (atomic `.md/.html` persistence with frontmatter), `ui/article_view.lua` (overlay, metadata/header, empty/error states, optional isolated `ReaderUI` open behind `open_in_reader_enabled=false`), `ui/actions.lua` (internal routes `open_hn:<id>`, `open_digest:<date>`, `refresh`, `close`; Lua fallback, no HTML-tap dependency). Dashboard includes an internal action to save/open a Phase 3 test article.
- Weather base (Phase 4): `lib/wmo.lua`, `lib/geocoding.lua` (Open-Meteo geocoding), `lib/weather.lua` (Open-Meteo forecast + `WeatherView` normalization), `lib/weather_state.lua` (cache-first load/stale/error messaging), dashboard integration, and minimal settings actions in `ui/menus.lua` (search place, set lat/lon, clear, toggle, refresh-on-open).
- Settings: `<KOReader settings dir>/kindlehome.lua` (managed via `LuaSettings`).
- Cache: `<DataDir>/cache/kindlehome/*.json` (`weather.json` used by F4); content paths per `storage_mode` follow `PLAN.md`/`AGENTS.md`.
