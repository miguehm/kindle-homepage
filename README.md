# Kindle Home (KOReader plugin)

Kindle Home is a KOReader homepage plugin (`kindlehome.koplugin`) for Kindle with clock/date, device status, weather, Hacker News via `hnmd`, and RSS/Atom (planned).

## Status

Draft scaffold (Phase 0). UI language: English.

## Installation

### Development (KOReader desktop Linux)

1. Copy or symlink the plugin folder into your KOReader plugins directory:
   - `~/.config/koreader/plugins/kindlehome.koplugin/`
2. Start/restart KOReader desktop.
3. Open the main menu and select **Kindle Home** to show the dashboard.

### Kindle device

1. Copy `kindlehome.koplugin/` to:
   - `/mnt/us/koreader/plugins/kindlehome.koplugin/`
2. **Restart KOReader** (required on Kindle for new plugins to load).
3. Open from the KOReader main menu (and later via Dispatcher/gestures).

## Notes

- Current build shows a static dashboard (no network, no persistence).
- Configuration, cache, and data paths will follow the project plan in `PLAN.md`.
