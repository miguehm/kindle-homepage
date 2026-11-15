# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, weather (Open-Meteo), and Hacker News via `hnmd` (`https://hnmd.miguehm.com/top`).

## Status

Phase 1 (offline dashboard) and Phase 2 (transversal base) implemented in code; **Phase 3 reading base, Phase 4 weather base, and Phase 5 HN/hnmd base (client, cache-first/stale state, dashboard section, article open/persist from markdown, minimal HN settings UI) implemented in repo**. **F1 device verification on Kindle, F2/F3/F4/F5 runtime verification and ledgers remain pending**. UI language: English. RSS/Atom support removed from scope (HN-only via `hnmd`).

## Installation (Kindle — target)

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu (and later via Dispatcher/gestures).

## Development (optional, auxiliary)

KOReader on Linux desktop may be used only for quick iteration (not a supported target). Copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader.

## Configuration

- **Settings file:** `<KOReader settings dir>/kindlehome.lua` (managed via `LuaSettings`).
- **HN/hnmd (Phase 5 base):**
  - Configure via Kindle Home settings menu: enable/disable HN, base URL, API key (masked in UI), max items (1–20).
  - Manual edit is also supported in `settings/kindlehome.lua`:
    - `hnmd_enabled` (bool)
    - `hnmd_base_url` (string, default `https://hnmd.miguehm.com`, sanitized to https)
    - `hnmd_api_key` (string, stored locally in plaintext by KOReader settings; **never logged**)
    - `hnmd_max_items` (1–20)
    - `hnmd_ttl_minutes` (TTL for `cache/hnmd.json`)
  - `401` responses are surfaced as actionable "Invalid API key" messages (no automatic retries). `503 warming_up` and offline/network errors fall back to cached HN data when available.
- **Weather:** location via search or lat/lon, cache-first Open-Meteo fetch with stale fallback.

## Notes

- Dashboard: local date/time and battery/network status, weather section, and HN section (rank/title/score/comments/author/domain with status/markdown indicators). Refresh is cache-first with reentry guard and WiFi prompt/fallback when user-initiated offline.
- Transversal modules: `lib/config.lua`, `lib/paths.lua`, `lib/cache.lua`, `lib/http.lua`, `lib/refresh.lua`, `lib/logger.lua`.
- Reading: `lib/render/md_to_html.lua`, `lib/article_store.lua`, `ui/article_view.lua`, `ui/actions.lua` (internal Lua routes, no HTML-tap dependency). HN articles with `status==ok` and markdown are rendered from `hnmd` markdown and persisted as `.md/.html` under `articles/hn/`. Ask HN items (`url == null`) use hnmd content only. External URL fetch is not supported (MVP+).
- Weather: `lib/wmo.lua`, `lib/geocoding.lua`, `lib/weather.lua`, `lib/weather_state.lua`.
- HN/hnmd: `lib/hnmd.lua`, `lib/hnmd_state.lua`, cache `cache/hnmd.json`.
- Cache: `<DataDir>/cache/kindlehome/*.json`; content paths per `storage_mode` follow `PLAN.md`/`AGENTS.md`.
- Security: API keys/authorization headers/sensitive payloads must not be logged; API key is local plaintext config and masked in UI.
