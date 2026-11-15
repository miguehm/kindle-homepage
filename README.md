# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, and (planned) weather, Hacker News via `hnmd`, and RSS/Atom.

## Status

Phase 1 (offline dashboard) and Phase 2 (transversal base: config/paths/cache/http/refresh, AGENTS) implemented in code. **F1 device verification on Kindle and F2 verification ledger still pending**. UI language: English.

## Installation (Kindle — target)

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu (and later via Dispatcher/gestures).

## Development (optional, auxiliary)

KOReader on Linux desktop may be used only for quick iteration (not a supported target). Copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader.

## Notes

- Current build: local dashboard with date/time, battery, and network status; refresh replaces the view (scroll may reset). No network fetch integrated in UI yet.
- Transversal modules: `lib/config.lua` (defaults/validation), `lib/paths.lua` (canonical paths, atomic writes helper), `lib/cache.lua` (versioned envelope, quarantine/recovery), `lib/http.lua` (timeouts/limits/typed errors), `lib/refresh.lua` (cache-first/stale/budget/reentry guard), `lib/logger.lua`.
- Settings: `<KOReader settings dir>/kindlehome.lua` (managed via `LuaSettings`).
- Cache: `<DataDir>/cache/kindlehome/*.json`; content paths per `storage_mode` follow `PLAN.md`/`AGENTS.md`.
