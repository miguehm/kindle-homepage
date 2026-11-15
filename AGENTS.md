# AGENTS.md — KindleHome plugin invariants

Scope: `kindlehome.koplugin/` (KOReader plugin, Kindle e-ink target). Desktop KOReader is auxiliary only.

## Platform and structure
- Target: **Kindle with KOReader**. Do not assume desktop-only APIs/behavior.
- Keep plugin autocontained under `kindlehome.koplugin/` (`lib/`, `ui/`, `_meta.lua`, `main.lua`). Follow `PLAN.md` structure/contracts.

## Security and privacy
- **Never log `hnmd_api_key`, auth headers, or sensitive payloads.** `logger.lua` must stay structured and secret-free.
- Treat API keys as local plaintext config (KOReader limitation); UI must mask by default when surfaced.

## Network and reliability
- All HTTP must go through `lib/http.lua`: timeouts, `http_max_bytes`, `User-Agent`, typed results `{ok,status,body,headers?,error_kind}`.
- Error kinds: `timeout, network, http_401, http_503, http_other, parse, too_large`.
- Retries: at most 1 for transient `timeout/network`; **never** retry-loop on `401`.
- Respect `refresh_budget_s` and sequential per-source fetches to avoid freezing UI. Cache-first with stale fallback (see `lib/cache.lua`, `lib/refresh.lua`).

## Storage and data integrity
- Cache: `<DataDir>/cache/kindlehome/*.json` with versioned envelope (`schema_version`, `fetched_at`, `ttl_seconds`, `source`, `status`, `error?`, `payload`). Corrupt/incompatible cache must be quarantined/regenerated without crashing.
- Use canonical paths via `lib/paths.lua`; create dirs on demand; safe filenames/slugs.
- **Atomic writes** (tmp + rename) for cache and persisted content (`.md/.html`).

## Config
- Centralize defaults/validation/sanitization in `lib/config.lua` (`LuaSettings`, `settings/kindlehome.lua`). Out-of-range/invalid values fall back to defaults.

## Quality
- No dead code; no silent broad exception swallowing that hides corruption/state bugs.
- Keep UI messages brief/actionable (no stack traces to end users).
- Record deviations and verification runs in `PLAN.md` ledgers when work diverges or is validated.
