# Changelog

## [2.5.0] - 2026-11-18

### Changed
- **Settings open as a floating modal card.** The gear now shows a bordered white panel centered at 80% of the screen width, with the dashboard still visible around it. The panel grows with the current menu level up to a capped height, so submenus paginate inside the card. The native TouchMenu close arrow, the Back key and a tap outside the card all close it; setting changes still repaint the dashboard only after the modal closes.

### Verification
- `./scripts/check_lua51.sh` PASS, `./scripts/check_invariants.sh` PASS (new floating-card guard) and `./scripts/smoke_ui.sh` PASS (17 smokes, including the new modal-panel smoke and card geometry/close assertions). Pending: Kindle PW5 visual check.

## [2.4.1] - 2026-11-18

### Fixed
- **The gear opens the settings menu at full width.** `TouchMenu` expects each entry of `tab_item_table` to be the item array itself; 2.4.0 wrapped the sections in a nested `item_table`, so the tab had zero items and rendered as a tiny empty frame. The gear now passes the settings array directly as the single tab, carrying `text` and `icon` as extra fields.

### Verification
- `./scripts/check_lua51.sh` PASS, `./scripts/check_invariants.sh` PASS (new guard for the flat tab shape) and `./scripts/smoke_ui.sh` PASS (the menus smoke asserts `#tab == #settings_items` and no nested `item_table`). Pending: Kindle PW5 check of the gear.

## [2.4.0] - 2026-11-18

### Added
- **Previous-page control in Top Stories.** The pager now shows both arrows, wraps symmetrically in both directions, and is hidden when there is only one page. New monochrome `prev.svg` / `prev-inverse.svg` assets match the redesigned `next` glyph (plain paths, no SVG transforms).
- **Visible refresh feedback.** The hero shows `Updating…` (with the last update time when known) before the blocking network work starts, so the user sees that the dashboard is refreshing; the final state replaces it with the rebuilt data or the existing brief error hint.
- **Settings inside Kindle Home.** The dashboard gear now opens a single-tab native `TouchMenu` with the plugin settings (Weather, Hacker News, Sections, Interface, Refresh/network, Paths/storage). Setting changes repaint the dashboard on closing the menu, never over it.

### Fixed
- **Tools → Kindle Home opens the dashboard directly** instead of an intermediate submenu.
- **Pager and active-tab icons are visible again.** KOReader's `IconWidget` flattens icons onto white by default, which made the white `*-inverse.svg` glyphs disappear against the inverted black button/pressed tab; inverse icons now keep their alpha channel.

### Verification
- `./scripts/check_lua51.sh` PASS, `./scripts/check_invariants.sh` PASS (new guards: direct Tools callback, in-dashboard `TouchMenu`, alpha on inverse icons, previous-page and refresh wiring) and `./scripts/smoke_ui.sh` PASS (16 smokes, including pager wrap/hidden pager, refresh indicator and deferred settings repaint). Kindle PW5 matrix pending.

## [2.3.1] - 2026-11-16

### Fixed
- **Dashboard elements are no longer vertically centered.** The fit path used `LeftContainer` with the full viewport height, which centers its child vertically (`y + (dimen.h - content.h)/2`) and left the content floating with large blank areas. The content now lives in a top-aligned `HorizontalGroup` with a real left margin, followed by a `VerticalSpan` filler that pushes the fixed bottom tab bar down; pages with few stories start directly under the header.
- **No more scroll bar with offline/refresh notices.** `refresh_hint`, `weather.message` and `hn.message` could show the same connectivity status three times, adding enough height to trigger the scroll fallback. A global hint now suppresses redundant per-source notices, and section gaps/card padding were slightly reduced.

### Changed
- **Row count degrades before scrolling.** Top Stories still prefers 4 rows, but if the measured content does not fit the available height the dashboard rebuilds its model with 3 rows, then 2, then 1. A native `ScrollableContainer` is created only when even a single row cannot fit (very large `ui_font_scale` or landscape). Pagination and the next-page control use the chosen row count; the bottom tab bar stays fixed outside the scroll area.

### Verification
- `./scripts/check_lua51.sh` PASS, `./scripts/check_invariants.sh` PASS (new guards: top-left anchoring with symmetric margins, no centering `LeftContainer`, 4→3→2→1 degradation before scroll, notice dedup) and `./scripts/smoke_ui.sh` PASS (dashboard smoke asserts the top-anchored tree, dedup of offline notices, a forced 3-row layout with tall text, and the native scroll fallback). Kindle PW5 matrix pending.

## [2.3.0] - 2026-11-16

### Changed
- **Dashboard fits one screen.** Top Stories now shows **4 rows per page** instead of 5. The "Last refreshed" footer section is gone: a compact relative time (`2 min ago`) now sits to the left of the refresh button in the Top Stories header. The body is built without a scroll container when its measured height fits the available viewport; a native `ScrollableContainer` is created **only** as a fallback when the content cannot fit (very large `ui_font_scale` or landscape), with the bottom tab bar always fixed outside it.

### Fixed
- **Unwanted vertical scroll on the dashboard at normal scales.** Removing a whole story row and the footer section, and no longer adding a gap after the last section, brings the PW5 (1236×1648, scale 1.0) content within the available body height.

### Verification
- `./scripts/check_lua51.sh` PASS, `./scripts/check_invariants.sh` PASS (new guards: measured scroll fallback, 4-row pagination, no body footer) and `./scripts/smoke_ui.sh` PASS (dashboard smoke covers both the fit path and the forced-overflow fallback path; 4 rows/page, compact header label). Kindle PW5 matrix pending.

## [2.2.0] - 2026-11-16

### Added
- **Paperwhite Monochrome dashboard.** Combined hero/weather card (clock with AM/PM, short date, last-update time, WiFi and battery glyph on the left; temperature, condition, H/L, place, wind, humidity and tomorrow on the right), separated by a hairline. Paginated **Top Stories** card with an inverted `Y/HN` badge, in-card refresh, five numbered rows and a `Page N of M` next-page control (wraps at the end; resets on refresh, preserved when returning from an article). Fixed three-tab bottom bar; **Dashboard** is active, **Todo's** and **Store** are placeholders with a brief “Coming soon” notice.
- **Custom dashboard header.** Literary serif title with settings and close buttons (settings opens the KOReader main menu, close keeps the existing exit path), wired to the Shell repaint target. Native `TitleBar`/action bar remain unchanged for the article fallback.
- **Monochrome SVG glyphs** for weather (sun/partly/cloud/fog/rain/snow/storm) and navigation, shipped under `assets/icons/`; sharp corners, discrete grays and binary inversion only.
- **12/24-hour clock** (`ui_clock_24h`, default `false` = 12 h with AM/PM) in the Interface menu.

### Changed
- **Weather payload extended** with current wind/humidity and a second forecast day (`forecast_days=2`, `wind_speed_unit=kmh`); additive, so older cache entries simply omit the new lines until their TTL expires. WMO codes now map to icon keys.
- Typography follows DESIGN.md scale with KOReader's bundled **Noto Serif** (display/body) and **Noto Sans** (labels), with fallback to `cfont`; Literata/Inter are not bundled and would break the plugin's self-contained install.
- Dashboard no longer uses the native action bar; refresh/close/settings live in the header and card as in the design.

### Fixed
- **Dashboard no longer fails to open.** `DashboardHeader` is now a real `InputContainer` widget (`getSize`/`paintTo`); previously it was a plain table and `Shell:init` crashed at `shell.lua:73` (`attempt to call method 'getSize'`). `Shell` also falls back to the native `TitleBar` if a custom header is not a valid widget.
- **No more KOReader crash on the first touch.** `BatteryGlyph` is now a `Widget` subclass; as a plain table it lacked `handleEvent()` and broke `WidgetContainer:propagateEvent` on any tap. The dashboard smoke now walks the whole widget tree asserting `handleEvent()` on every child (negative test reproduces the old crash).

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS (new guards for modular widgets, assets and sharp corners), `scripts/smoke_ui.sh` PASS (15 smokes incl. new `weather.lua` and rewritten `dashboard.lua` with pagination, header, nav and crop region; the header is asserted to expose `getSize`/`paintTo`, an invalid header must fall back, and every child in the widget tree must expose `handleEvent`).
- Real KOReader/Linux modules (LuaJIT, PW5-scaled screen) rendered the full Shell (header + body) to PNG: no paint errors, correct header/body layout. A first Kindle PW5 attempt failed at `shell.lua:73`; the fix was reproduced and re-verified with real modules. **Kindle PW5 re-verification pending** (see `PLAN.md` §10).

## [2.1.0] - 2026-11-16

### Added
- **Custom content folder.** Nueva clave `custom_content_dir` y opción **Choose custom content folder** en Paths and storage: ruta absoluta arbitraria y anidada para los documentos descargados (p. ej. `/mnt/us/My Docs/KindleHome`). Se rechazan rutas relativas, segmentos `..` y el directorio de instalación de KOReader; vacía restaura `storage_mode`/`documents_subdir`. Las rutas se resuelven solo en `lib/paths.lua`; la caché permanece en `<DataDir>`.
- **Selector nativo de carpetas (F15.4).** La carpeta se elige con el `PathChooser` de KOReader (modo solo directorio, con creación de carpetas y navegación paginada) en lugar de escribir la ruta; la entrada **Reset custom content folder** vuelve a la ubicación por defecto. Ambos comparten la validación/sanitización existente.

### Fixed
- **Elementos detrás del título.** El Shell pinta ahora un fondo blanco opaco a pantalla completa antes de dibujar sus hijos (`Shell:paintTo`), porque `TitleBar` es un `OverlapGroup` transparente y `covers_fullscreen` impide que UIManager repinte la pantalla anterior. El `TitleBar` también recibe `show_parent = self` como destino de repintado. Los cierres usan refresco `full`.
- **Visibilidad de rutas.** "Documents subdir" y "Storage mode" se marcan como *(fallback)* cuando hay una carpeta custom activa, y "Show resolved paths" pasa a "Show active content paths".

### Changed
- **Sin migración de archivos.** Al cambiar de carpeta, los `.md/.md.html` y link cards ya descargados permanecen en su ubicación anterior y se descargan de nuevo al abrirlos; no se copian ni se borran (invariante de AGENTS.md).

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS, `scripts/smoke_ui.sh` PASS (15 smokes: nuevos `shell_paint.lua` — cobertura opaca del header — y `paths.lua` — carpeta custom, fallback, rutas canónicas y escritura atómica; `config.lua`/`menus.lua` ampliados).
- **Verificación en Kindle PW5 PASS (2026-11-16, confirmada por el usuario):** header sin iconos de la pantalla anterior y carpeta custom absoluta/anidada con persistencia y descarga correctas (F15.1–F15.3; registro en `PLAN.md` §10).
- **F15.4 (selector nativo + Reset):** gates PASS con 4 pickers simulados en el smoke de menús; pendiente de verificación en Kindle. Se añade a este mismo release 2.1.0 porque aún no se había publicado.

## [2.0.0] - 2026-11-16

### Removed
- **Digest (breaking change).** Eliminado `lib/digest.lua` y todas sus integraciones: tarjeta y botón del dashboard, acciones `generate_digest`/`open_digest`, ajuste `show_digest`, ruta `digest/`, ramas en `ArticleStore` y referencias en docs/smokes. Los archivos `digest/*.md/.html` ya generados en el dispositivo **no se borran**.

### Added
- **Link cards persistentes.** Si falla la descarga y no hay copia local, se escribe/abre `<id>-<slug>-links.md` (y su `.md.html`) con la URL de HN, la URL de origen (o “Ask HN”) y el motivo del error. La tarjeta permanece en la biblioteca incluso si luego la descarga tiene éxito.
- **Enlaces reales en el documento.** La meta del `.md.html` incluye `<a href>` para la conversación de HN y la URL de origen; al tocarlos en `ReaderUI`, KOReader ofrece Copiar / QR / Abrir en navegador. Los `.md.html` antiguos se regeneran mediante una marca de esquema de render.

### Fixed
- **Crash de menús.** `prompt_text` ya no inserta un botón `nil` en la fila de `InputDialog` (causa de los crashes al abrir clima o “Documents subdir”). El botón Clear del API key cierra correctamente su diálogo.
- **Clima sin ubicación.** `weather_lat`/`weather_lon` (defaults `nil`) ahora se pueden guardar y recargar desde `settings/kindlehome.lua`; antes `Config:set` los rechazaba y el clima nunca consultaba la API.

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS, `scripts/smoke_ui.sh` PASS (12 smokes: nuevos `config.lua`, `menus.lua` y `link_card.lua`; dashboard/action bar sin digest; renderer con enlaces y marca de migración).
- **Verificación en Kindle PW5 PASS (2026-11-16, confirmada por el usuario):** matriz F14 completa — menús Weather/Documents subdir sin crash, coordenadas persistentes tras reinicio, digest ausente, link cards con URLs, enlaces en el documento, lectura sin regresión, instalación limpia desde `kindlehome.koplugin-v2.0.0.zip` y `crash.log` limpio. Registrada en `PLAN.md` §10.

## [1.0.0] - 2026-11-16

### Changed
- **MVP release candidate.** Versión final del artefacto de release; repositorio, gates y documentación listos para el cierre con evidencia en Kindle (`PLAN.md` F13).
- **Retorno desde el lector nativo al dashboard.** `Dashboard` mantiene su shell vivo debajo de `ReaderUI` cuando el artículo se abre en el lector; al cerrar el lector se vuelve al dashboard en lugar del explorador de archivos. El fallback paginado cierra el dashboard como antes; si `ReaderUI` falla al abrir, se cierra y se muestra el pager (`on_fallback`). Aplica también a artículos de prueba y digests.

### Fixed
- `ArticleView:show` ahora comprueba el valor devuelto por `openInReader`: un `ReaderUI:showReader` que falla silenciosamente (`false`) ya no impide el fallback al pager.

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS, `scripts/smoke_ui.sh` PASS (9 smokes; dashboard comprueba que el shell permanece bajo `ReaderUI` y que el fallback lo cierra; article_view comprueba `will_open_in_reader`, apertura correcta y fallback tras fallo del lector).
- **Verificación en Kindle PW5 PASS (2026-11-16, confirmada por el usuario):** matriz F13 completa — pager de artículos, retorno desde `ReaderUI` al dashboard, UI/e-ink (retrato/apaisado, S–XL), descargas reales y estados de error, clima, digest, menús/Dispatcher, rendimiento/seguridad e instalación limpia desde zip. Registrada en `PLAN.md` §10; MVP cerrado.

## [0.4.1] - 2026-11-16

### Changed
- **Fallback de artículos con paginación nativa.** `ui/article_html_pager.lua` sustituye a `ScrollHtmlWidget`: usa `HtmlBoxWidget` a tamaño viewport, `VerticalScrollBar` e input nativo (swipe, tap en mitades, **pan/release** y teclas PgFwd/PgBack). Arrastrar lentamente avanza de página (antes no respondía). El lector nativo `ReaderUI` sigue siendo la vía principal.
- Retirado `ScrollHtmlWidget` de todo el plugin; la selección de texto del fallback se retira (disponible en `ReaderUI`).
- La tarjeta/visor de error nunca usa `kh:*` en el HTML; la navegación Back/Close sigue en la barra nativa.

### Added
- Config dev-only `ui_force_article_fallback` (default `false`) para forzar el pager y poder validarlo en Kindle sin depender de que `ReaderUI` falle. No se expone en menús.

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS (prohíbe `ScrollHtmlWidget` en todo el plugin; exige `HtmlBoxWidget` + `VerticalScrollBar` en el pager), `scripts/smoke_ui.sh` PASS (9 smokes: dashboard, article_view, pager, shell, action_bar, md_render, article_download, hnmd_url, http_stream).
- Pager smoke: 3 páginas, swipe/tap/pan-release/teclas/ratio, repintado hacia el `Shell` y caso de una sola página. Instanciación con módulos reales v2026.07.1: 41 páginas, cambio de página OK.

## [0.4.0] - 2026-11-16

### Changed
- **Dashboard con interfaz nativa.** El cuerpo HTML (`ScrollHtmlWidget` + CSS) se sustituye por un árbol de widgets de KOReader (`TextBoxWidget`/`TextWidget`/`FrameContainer`/`LineWidget`) dentro de un `ScrollableContainer`: scroll continuo por pan y paginado por flick, con scrollbar nativa. El reloj/fecha, estado, clima, HN y digest se construyen como widgets; el tap en un titular usa la misma ruta `kh:hn:<id>` de siempre.
- La tarjeta DIGEST ya no contiene el enlace “Open latest digest”: solo informa del estado; el botón Digest de la barra nativa genera/abre el resumen.
- Eliminados `lib/render/dashboard_html.lua` y `Theme.dashboard_css` (código muerto).

### Added
- `lib/dashboard_model.lua`: modelo de vista puro (sin dependencias de KOReader) que normaliza `state` a secciones/filas; permite verificar el dashboard en Lua 5.1 sin stubs de widgets.
- `ui/dashboard_body.lua`: constructor del cuerpo nativo con anchos calculados para evitar scroll horizontal y `LeftContainer` como hijo único del contenedor de scroll.
- `Shell` registra `cropping_widget` cuando el cuerpo sabe recortar (`ScrollableContainer`).

### Verification
- `scripts/check_lua51.sh` PASS, `scripts/check_invariants.sh` PASS (nuevos guards: dashboard sin HTML/`ScrollHtmlWidget`, cuerpo nativo con `ScrollableContainer`, sin `dashboard_html.lua`), `scripts/smoke_ui.sh` PASS (modelo con 10 filas, viewport 1200×1400, hijo único ancho 1170, 11 taps → `open_hn:*`, `cropping_widget`).
- Instanciado con módulos reales de KOReader v2026.07.1 (LuaJIT): cuerpo 1236×1400, contenido 1200×2380 → scrollable sin desbordamiento horizontal. Verificación en Kindle PW5 pendiente.

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
