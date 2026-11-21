# Contributing to Kindle Home

Thanks for helping improve Kindle Home. This document describes how to get a
change from your checkout into a release.

## Ways to contribute

- **Issues:** report bugs with your KOReader version, device and `crash.log`
  excerpt (never paste API keys or tokens). Feature requests are welcome too.
- **Docs:** fix inaccurate setup steps, configuration tables or troubleshooting
  entries in `README.md`.
- **Code:** bug fixes, small features and device-specific improvements. Keep
  changes focused and explain how you verified them.
- **Translations:** user-facing strings use KOReader's `_()` gettext helper.

## Development setup

1. Clone the repository and create a branch from `main`.
2. Install a Lua 5.1-compatible engine (`lua5.1` or `luajit`). A newer system
   `luac` is not enough: it accepts syntax that crashes KOReader on Kindle.
3. Optionally symlink `kindlehome.koplugin/` into your desktop KOReader plugins
   directory for quick iteration. Desktop is auxiliary only; final validation
   must happen on a Kindle.
4. Run the three gates before opening a pull request:

```bash
./scripts/check_lua51.sh      # Lua 5.1/LuaJIT syntax
./scripts/check_invariants.sh # structural invariants
./scripts/smoke_ui.sh         # offline widget rendering and action wiring
```

They are also run by CI on every push and pull request.

## Code conventions

- Lua 5.1 / LuaJIT only: no bitwise operators, integer division, `goto`,
  `table.unpack` or other 5.2+ APIs.
- Keep plugin code self-contained under `kindlehome.koplugin/`.
- All HTTP goes through `lib/http.lua` (timeouts, byte caps, typed results).
  Article bodies are streamed to a temporary file and promoted with `rename`;
  never buffer an article in memory.
- UI code must not perform HTTP or delete/rename files directly. Use the
  model/store layers.
- Use atomic writes for cache and persisted content.
- Never log the API key, authorization headers or sensitive payloads.
- Keep user-facing messages short and centralized in `ui/messages.lua`.
- `AGENTS.md` lists the invariants that must never be broken.

## Branch and PR workflow

- Use small, descriptive branches, e.g. `fix/weather-cache-ttl` or
  `docs/install-steps`.
- Target `main`. Describe what changed, why, and how you verified it (including
  device model and KOReader version when relevant).
- All gates must pass. CI runs them on a clean checkout; a local pass is not a
  substitute for green CI.
- Keep commits focused and use Conventional Commits:

```
feat(ui): add configurable Top Stories rows
fix(http): tolerate truncated responses
docs(readme): clarify release zip installation
```

Allowed types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`.

## Versioning and releases

Versions follow SemVer (`MAJOR.MINOR.PATCH`). The authoritative version is
`kindlehome.koplugin/_meta.lua`; update it in the same change that updates
`CHANGELOG.md`. Release artifacts are attached to GitHub Releases rather than
committed to the source tree.

## License and conduct

By contributing you agree that your contributions are licensed under the
MIT License (see [LICENSE](LICENSE)). Participation is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).
