# Changelog

## [0.3.1] - 2026-11-16

### Fixed
- **El dashboard y el fallback de artículos no desplazaban (parpadeaban sin cambiar el contenido).** `ScrollHtmlWidget` llama `UIManager:setDirty(self.dialog, ...)` al desplazar, pero `UIManager` solo marca como *dirty* los widgets presentes en `_window_stack`. `dialog` apuntaba al propio cuerpo (anidado en el `Shell`), así que se encolaba el refresh de e-ink pero nunca se pintaba la página siguiente. `Shell:init` cablea ahora `body.dialog`, `body.show_parent` y `body.htmlbox_widget.dialog` al `Shell`, que sí es el widget mostrado. Se eliminaron las auto-asignaciones `dialog = body/widget` en `ui/dashboard.lua` y `ui/article_view.lua`.

### Added
- `Logger.info("shell", "layout", …)` con `screen_w/h`, `header`, `footer`, `body_h` y `fullscreen` (estructurado, sin secretos) para confirmar el layout en dispositivo.

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS (invariante 1 reescrito: el destino de repintado debe ser el widget de nivel superior; prohibida la auto-asignación de `dialog`), `scripts/smoke_ui.sh` PASS (8 smokes; dashboard/article/shell comprueban `dialog == shell` y `show_parent == shell`).
- Diagnóstico en Kindle PW5 / KOReader v2026.07: pantalla 1236×1648, cuerpo ≈1400 → `getPages() = 4` (paginación correcta); swipe/tap producían flash sin repintado; sin tracebacks; artículos se abren en `ReaderUI`. Tras instalar 0.3.1 el dashboard vuelve a desplazarse (validado en dispositivo, navegación por flick/tap OK).

## [0.3.0] - 2026-11-16

### Changed
- **Artículos HN como archivos Markdown descargados (contrato `hnmd` real).** `GET /v1/top` se usa solo como índice de metadatos (`schema_version`, `content_status`, `content_url`, `content_length`); al pulsar un ítem se descarga `GET /v1/articles/{id}.md` en `<content root>/articles/hn/<id>-<slug>.md` y se genera `<id>-<slug>.md.html` para abrirlo con `ReaderUI`.
- `hnmd_base_url` por defecto pasa a `https://hnmd.miguehm.com/v1`; un host sin path recibe `/v1`. `content_url` se resuelve contra el origen (evita `/v1/v1/...`) y se rechazan URLs de otro origen.
- Descarga **streaming a archivo** (`Http.get_to_file`): nunca se acumula el cuerpo en RAM (PW5 con ~15 MB libres), con límites `index_max_bytes` (128 KiB) y `article_max_bytes` (512 KiB), validación de `Content-Length` y `os.rename` atómico.
- `Cache.SCHEMA_VERSION` a 2: cachés con payload completo anterior se ponen en cuarentena y se regeneran.
- Re-descarga solo si el `.md` local falta/vacío; `404`, `503` o fallos de red **no** borran la copia local. No se usan `etag`/`last-modified`.
- Renderizador extendido: `h4`–`h6`, `blockquote`, `hr`, imágenes reducidas a su texto alternativo (sin cargas remotas), `<!DOCTYPE html>` y `<title>` en documentos persistidos.
- Eliminado `open_in_reader_enabled`: el lector nativo es el flujo por defecto; el overlay queda como fallback (Markdown crudo si el render falla).

### Added
- `lib/hnmd.lua`: `fetch_index` + `download_article` + `resolve_content_url` (validación de esquema/id/estados).
- `lib/article_store.lua`: `ensure_local`, `is_local`, `render_derived` (regenera HTML si el `.md` es más reciente) y detección de frontmatter propio.
- `lib/paths.lua`: `article_md_path` / `article_html_path`.
- Errores tipados `http_404` e `incomplete`; mensajes `no_content`, `warming_up`, `offline_no_local`, `downloading`.
- Smokes nuevos: `article_download.lua` (promoción/atomicidad/404 conserva copia/`.tmp` limpio), `md_render.lua` (extensiones y escape), `hnmd_url.lua` (resolución `/v1`, cross-origin, índice/límites), `http_stream.lua` (sink por chunks, `Content-Length`, `too_large`, 404/503 sin retry, timeout con 1 retry).

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS (nuevos guards: descarga vía `get_to_file`, `ui/` sin HTTP/borrado, `os.remove/rename` solo sobre `.tmp`), `scripts/smoke_ui.sh` PASS (8 smokes).
- Backend validado con datos reales (`/v1/top`, `HEAD`/`GET` de `50517488` 7938 B y `50516473` 72644 B, 401 con `WWW-Authenticate`). Verificación en Kindle PW5 pendiente.

## [0.2.1] - 2026-11-15

### Changed
- **Apertura de artículos por defecto en el lector nativo de KOReader.** Los artículos y digests con documento `.html` persistido localmente se abren ahora con `ReaderUI:showReader(path)` en lugar del overlay `ScrollHtmlWidget`, lo que habilita selección de texto, anotaciones, subrayados, diccionario, progreso y modo nocturno, todo offline y sin red.
- El overlay `ScrollHtmlWidget` se mantiene solo como fallback cuando no existe `.html` local o el lector no está disponible; en ese fallback se activó `highlight_text_selection = true` para permitir selección de texto.

## [0.2.0] - 2026-11-15

### Changed
- **UI redesigned for Kindle PaperWhite 5.** Absolute `font-size` CSS (px) replaced with relative `em` units; HTML base size now derives from KOReader's DPI-scaled `default_font_size`, so body text renders legibly on 300 ppi screens.
- **Hybrid native + HTML shell.** `ui/shell.lua` (`covers_fullscreen` + `TitleBar` + scrolling HTML body + `ui/widget/action_bar.lua`) replaces bare `ScrollHtmlWidget`. Full refresh (`setDirty(..., "full")`) at open/close to limit e-ink ghosting.
- **Always-visible exit paths:** TitleBar exit icon, footer "Exit" action, Back key, and swipe-down on the header.
- **Native action bar:** icon + short label per button (Refresh, Digest, Exit), targets ≥ ~58 dp, MDLight icons (no unreliable unicode glyphs in HTML).
- **Dashboard markup** (`lib/render/dashboard_html.lua`): hero clock/date, one Hacker News list (no duplicated "Actions"), full titles, relative times, weather/card/digest sections.
- **Article/digest overlay** on the same shell: Back (chevron.left), optional Reader, Close; navigation no longer at end of HTML.
- **Interface menu:** text size S/M/L/XL (`ui_font_scale`), fullscreen toggle, test-article link toggle.
- **Text sizes scale** with `ui_font_scale` for both HTML body and native buttons.

### Added
- `lib/render/theme.lua`: UI scale tokens, `covers_fullscreen`, em-only dashboard/article CSS.
- `lib/render/dashboard_html.lua`: dashboard body fragment builder.
- `ui/shell.lua`: fullscreen shell widget.
- `ui/widget/action_bar.lua`: native icon+label action bar.
- `scripts/smoke/shell.lua`, `scripts/smoke/action_bar.lua`: offline Lua 5.1 smoke tests.

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS, `scripts/smoke_ui.sh` PASS (dashboard/article/shell/action_bar).
- Device runtime verification (legibility, targets, rotation, ghosting) pending Kindle PW5 testing.

## [0.1.2] - 2026-11-15

### Fixed
- **Blocking crash on first swipe/tap (device-confirmed).** `ScrollHtmlWidget` was created without `dialog`; its scroll handlers do `self.dialog.movable` (`frontend/ui/widget/scrollhtmlwidget.lua:182` on KOReader v2026.07), so any swipe/tap in the dashboard or article view raised `attempt to index field 'dialog' (a nil value)` and KOReader aborted. Both widgets now set `widget.dialog = widget` before `UIManager:show`.
- **Actions were never rendered.** `actions`/`title` are not `ScrollHtmlWidget` fields, so the dashboard showed text referring to buttons that could not exist. Actions are now real HTML links (`kh:refresh`, `kh:digest`, `kh:digest:latest`, `kh:hn:<id>`, `kh:test`, `kh:close`, and `kh:back`/`kh:dashboard`/`kh:reader` in articles) routed through `html_link_tapped_callback`.
- **Nested HTML documents.** Dashboard/article bodies are now passed as fragments with their stylesheet via the `css` option (`MdToHtml.document_body` added); persisted `.html` files still use the full document.
- **`Actions:dispatch` argument misuse.** Calls now use the `prefix:arg` form (`open_hn:<id>`, `open_digest:<date>`); the old extra arguments were silently ignored.
- Refresh failures are logged with the actual error instead of a bare `refresh_failed`.

### Changed
- `refresh_on_open` now defaults to **false** (MVP): opening always paints cached state and never blocks on HTTP; when enabled, the refresh is deferred with `UIManager:scheduleIn` after the first paint.
- `http_timeout_s` default 10 → 6 s and `http_max_bytes` 512 → 256 KiB (device had ~15 MB free RAM).
- Content is written to the Kindle library (`/mnt/us/documents/KindleHome`) instead of inside the KOReader install dir (`getFullDataDir()` returns `/mnt/us/koreader` on Kindle).

### Added
- `scripts/check_invariants.sh`: static guards (ScrollHtmlWidget requires `dialog`; no nonexistent `ui/elements/menu_items`).

### Verification
- Device: KOReader v2026.07 / LuaJIT 2.1.1783773675, Kindle PaperWhite 5. Evidence in `PLAN.md` §9/§10 (3 tracebacks at `scrollhtmlwidget.lua:182` after `[KindleHome] event=shown`).
- Repo: `check_lua51.sh` PASS (22 files), `check_invariants.sh` PASS (and negative test fails as expected). **Interactive re-test on device (scroll/tap in all directions, HN article, digest) pending.**

## [0.1.1] - 2026-11-15

### Fixed
- **Blocking: plugin failed to load on device.** `lib/paths.lua` used a Lua 5.3 bitwise XOR (`~`) in `short_hash`; KOReader on Kindle (Lua 5.1/LuaJIT) rejected `main.lua` with `unexpected symbol near '~'`, so `init()` never ran and the plugin was absent from all menus and from Plugin management. Replaced with a pure-arithmetic hash (no bitwise operators), safe on Lua 5.1.
- **Settings submenu never registered.** `ui/menus.lua` required the nonexistent `ui/elements/menu_items` module and registered the menu outside KOReader's official hook; `main.lua` silenced the failure with `pcall`. Now a single **Kindle Home** entry (Open dashboard + Weather, Hacker News, Sections, Refresh & network, Paths/storage) is registered through `addToMainMenu(menu_items)`.
- Removed `pcall` around menu registration and dead code in `main.lua`; removed deprecated `name` field from `_meta.lua`; release zip no longer contains empty `lib/rss/` directories.

### Added
- `scripts/check_lua51.sh`: mandatory Lua 5.1/LuaJIT syntax gate (`luac5.1`/`lua5.1`/`luajit`) for all plugin files, documented in `AGENTS.md` and `README.md`. A system `luac` 5.3+ is not a valid substitute.

### Verification
- Repo (2026-11-15, Linux dev): `luac5.1 -p` PASS for all 22 `kindlehome.koplugin/**/*.lua`; before the fix it reproduced the device error at `lib/paths.lua:55`. Negative test confirmed the gate fails on synthetic Lua 5.3 bitwise syntax.
- Device evidence (v0.1.0 failure) and the gate run are recorded in `PLAN.md` §9/§10. **Reinstall 0.1.1 on Kindle and confirm the plugin loads (no `WARN Error when loading` in `crash.log`) remains pending.**

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
- Repo/static (2026-11-15, Linux dev): `luac -p` passed for all `kindlehome.koplugin/**/*.lua` (**superseded**: the system `luac` was 5.5, not Lua 5.1/LuaJIT — see 0.1.1); logger/HTTP/UI audit showed no API key, Authorization header, or payload logging.
- **Kindle (KOReader) runtime/device validation:** required for MVP closure (F1–F8 matrix: offline/unstable WiFi, 401/503/parse/too_large, geocoding/TTL, cache corruption, digest/reading, Dispatcher/Profiles/gestures, performance). Not executed in this environment; record results in `PLAN.md` §10.

### Deferred (post-MVP)
- 8.6: alternative HN fallback, full i18n, screensaver/userpatch.
- 5.10: external URL fetch/open in overlay.
