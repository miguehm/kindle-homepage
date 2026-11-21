# AGENTS.md — KindleHome plugin invariants

Scope: `kindlehome.koplugin/` (KOReader plugin, Kindle e-ink target). Desktop KOReader is auxiliary only.

## Platform and structure
- Target: **Kindle with KOReader**. Do not assume desktop-only APIs/behavior.
- Keep plugin autocontained under `kindlehome.koplugin/` (`lib/`, `ui/`, `_meta.lua`, `main.lua`). Follow `PLAN.md` structure/contracts.

## Security and privacy
- **Never log `hnmd_api_key`, auth headers, or sensitive payloads.** `logger.lua` must stay structured and secret-free.
- Treat API keys as local plaintext config (KOReader limitation); UI must mask by default when surfaced.

## Network and reliability
- All HTTP must go through `lib/http.lua`: timeouts, byte caps, `User-Agent`, typed results `{ok,status,body,headers?,error_kind}`.
- Article bodies are downloaded with `Http.get_to_file` (streaming to a `.tmp` file, `os.rename` on success); never buffer an article in RAM. The in-memory `Http.get` is for small JSON only (`/v1/top`, weather).
- Error kinds: `timeout, network, http_401, http_404, http_503, http_other, parse, too_large, incomplete`.
- Retries: at most 1 for transient `timeout/network`; **never** retry-loop on `401`.
- Respect `refresh_budget_s` and sequential per-source fetches to avoid freezing UI. Cache-first with stale fallback (see `lib/cache.lua`, `lib/refresh.lua`).

## Storage and data integrity
- Downloaded articles: only the canonical `<content root>/articles/hn/<id>-<slug>.md` is persisted in the content folder (never rekeyed by rank). The HTML needed by KOReader's native reader is rendered to `<DataDir>/cache/kindlehome/articles/` and removed when the reader/fallback closes; legacy adjacent `.md.html` files are migrated on startup. Never delete a local `.md` copy because of `404`/network errors.
- Cache: `<DataDir>/cache/kindlehome/*.json` with versioned envelope (`schema_version`, `fetched_at`, `ttl_seconds`, `source`, `status`, `error?`, `payload`). Corrupt/incompatible cache must be quarantined/regenerated without crashing.
- Use canonical paths via `lib/paths.lua`; create dirs on demand; safe filenames/slugs.
- **Atomic writes** (tmp + rename) for cache and persisted content (`.md/.html`).

## Config
- Centralize defaults/validation/sanitization in `lib/config.lua` (`LuaSettings`, `settings/kindlehome.lua`). Out-of-range/invalid values fall back to defaults.

## Quality
- No dead code; no silent broad exception swallowing that hides corruption/state bugs.
- Keep UI messages brief/actionable (no stack traces to end users). Prefer centralized mapping in `ui/messages.lua` for user-facing states/errors.
- Record deviations and verification runs in `PLAN.md` ledgers when work diverges or is validated.

## Lua dialect (hard requirement)
- KOReader on Kindle runs **Lua 5.1 / LuaJIT**. Do not use Lua 5.2+ syntax: no bitwise operators (`~ & | << >>`), no integer division `//`, no `goto`/labels, no `table.unpack`/`math.tointeger`-only paths.
- Mandatory gates before release: `./scripts/check_lua51.sh` (Lua 5.1/LuaJIT syntax; uses `luac5.1`/`lua5.1`/`luajit`) , `./scripts/check_invariants.sh` (native scroll bodies only — no `ScrollHtmlWidget`; dashboard fits one screen, is top-left anchored, degrades story rows from the configured preferred count (default 4) down to 1 before scrolling and uses `ScrollableContainer` only as a measured last resort; article fallback uses the native pager; `Shell` wires `dialog`/`show_parent` to the top-level widget, menu registration, streamed downloads) and `./scripts/smoke_ui.sh` (offline Lua 5.1 rendering of dashboard/article, fit, adaptive-row and fallback paths, with stubbed KOReader modules). A system `luac` from 5.3+ is **not** a valid substitute: it accepts syntax that fails on device.
- Plugin load failures surface as `WARN Error when loading .../main.lua` in KOReader `crash.log`; treat any such line as a blocking defect.
