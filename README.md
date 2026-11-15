# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) focused on **Kindle (e-ink)**. It provides clock/date, device status, and (planned) weather, Hacker News via `hnmd`, and RSS/Atom.

## Status

Phase 1 (offline dashboard) implemented in code; **device verification on Kindle pending**. UI language: English.

## Installation (Kindle — target)

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu (and later via Dispatcher/gestures).

## Development (optional, auxiliary)

KOReader on Linux desktop may be used only for quick iteration (not a supported target). Copy/symlink to `~/.config/koreader/plugins/kindlehome.koplugin/` and restart KOReader.

## Notes

- Current build: local dashboard with date/time, battery, and network status; refresh replaces the view (scroll may reset). No network fetch yet.
- Settings: `<KOReader settings dir>/kindlehome.lua` (created/managed via `LuaSettings`).
- Cache/data paths and online features follow `PLAN.md`.
