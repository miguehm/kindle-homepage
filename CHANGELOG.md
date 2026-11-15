# Changelog

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
- Repo/static (2026-11-15, Linux dev): `luac -p` passed for all `kindlehome.koplugin/**/*.lua`; logger/HTTP/UI audit showed no API key, Authorization header, or payload logging.
- **Kindle (KOReader) runtime/device validation:** required for MVP closure (F1–F8 matrix: offline/unstable WiFi, 401/503/parse/too_large, geocoding/TTL, cache corruption, digest/reading, Dispatcher/Profiles/gestures, performance). Not executed in this environment; record results in `PLAN.md` §10.

### Deferred (post-MVP)
- 8.6: alternative HN fallback, full i18n, screensaver/userpatch.
- 5.10: external URL fetch/open in overlay.
