# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, weather (Open-Meteo), and Hacker News via `hnmd` (`https://hnmd.miguehm.com/top`).

## Status

Phase 1 (offline dashboard) and Phase 2 (transversal base) implemented in code; **Phases 3–7 bases implemented in repo** (reading/persistence, weather, HN/hnmd, digest, full settings menu, Dispatcher/refresh policy hardening, centralized UI messages, limits enforcement). **F1–F7 runtime verification on Kindle and ledger closure remain pending** (device/KOReader runtime required). UI language: English. RSS/Atom support removed from scope (HN-only via `hnmd`).

## Installation (Kindle — target)

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu, assign the `Kindle Home` Dispatcher action to a gesture/Profile (e.g. open on wake/start) in KOReader, or launch manually.

## Development (optional, auxiliary)

KOReader on Linux desktop may be used only for quick iteration (not a supported target). Copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader.

## Configuration

- **Settings file:** `<KOReader settings dir>/kindlehome.lua` (managed via `LuaSettings`, defaults/sanitization in `lib/config.lua`).
- **Settings menu (Kindle Home):** Weather (enable/show, location search/lat-lon/clear, TTL), Hacker News (enable/show, base URL, API key masked, max items, TTL), Sections toggles (battery/network/digest), Refresh & network (`refresh_on_open`, `refresh_budget_s`, `http_timeout_s`, `http_max_bytes`), Paths/storage (mode, subdir, resolved paths).
- **HN/hnmd:**
  - Configure via UI or manual edit in `settings/kindlehome.lua`:
    - `hnmd_enabled`, `show_hn` (bool)
    - `hnmd_base_url` (string, default `https://hnmd.miguehm.com`, sanitized to https)
    - `hnmd_api_key` (string, stored locally in plaintext by KOReader settings; **never logged**, masked in UI)
    - `hnmd_max_items` (1–20), `hnmd_ttl_minutes`
  - `401` is actionable and never auto-retried. `503 warming_up`, offline/network/timeout/parse/too_large fall back to cached HN when available.
- **Weather:** enable/show toggles, location via search or lat/lon, `weather_ttl_minutes`, cache-first Open-Meteo fetch with stale fallback.
- **Refresh policy:** cache-first; on open refresh is conditioned by `refresh_on_open`, connectivity, TTL/stale state and `refresh_budget_s` (sequential per-source, reentry-guarded, brief progress/status messages).

## Notes

- Dashboard: local date/time and battery/network status, weather, HN and digest sections (toggleable). Refresh is cache-first with TTL/network/budget checks, reentry guard, WiFi prompt/fallback, and brief progress/status messages.
- Dispatcher: action `kindlehome_show_dashboard` registered for gestures/Profiles (safe, idempotent open; respects refresh policy).
- Transversal modules: `lib/config.lua`, `lib/paths.lua`, `lib/cache.lua`, `lib/http.lua`, `lib/refresh.lua`, `lib/logger.lua`.
- UI: `ui/dashboard.lua`, `ui/article_view.lua`, `ui/actions.lua`, `ui/menus.lua`, `ui/messages.lua` (centralized brief/actionable messages).
- Reading: `lib/render/md_to_html.lua`, `lib/article_store.lua` (internal Lua routes). HN articles with `status==ok` and markdown are rendered from `hnmd` markdown and persisted as `.md/.html` under `articles/hn/`. Ask HN items (`url == null`) use hnmd content only. External URL fetch is not supported (MVP+).
- Weather: `lib/wmo.lua`, `lib/geocoding.lua`, `lib/weather.lua`, `lib/weather_state.lua`. HN: `lib/hnmd.lua`, `lib/hnmd_state.lua`. Digest: `lib/digest.lua`.
- Limits: HTTP timeout/max-bytes and `refresh_budget_s` enforced; `hnmd_max_items` capped per cycle; `too_large`/budget errors degrade to cache/state messages.
- Cache: `<DataDir>/cache/kindlehome/*.json`; content paths per `storage_mode` follow `PLAN.md`/`AGENTS.md`.
- Security: API keys/authorization headers/sensitive payloads must not be logged; API key is local plaintext config and masked in UI.
