# Plan de implementación — Kindle Home (plugin KOReader)

> Objetivo: plugin KOReader (`kindlehome.koplugin`) tipo “homepage” para Kindle (KUAL + KOReader) con reloj/fecha, estado del dispositivo, clima (Open-Meteo), **Hacker News vía `hnmd`** y RSS/Atom; lectura en Markdown (persistencia `.md` + render HTML en crengine).  
> Fuente técnica base: investigación 2026-11-15 sobre KOReader v2026.07.1 en `/usr/lib/koreader`.  
> Este documento es el **contrato de implementación** (fases, dependencias, criterios, riesgos y registros). **No iniciar implementación** fuera de lo que la fase activa autorice.

## 1) Estado, alcance y convenciones

- **Estado del repo:** scaffold Fase 0 y dashboard offline Fase 1 implementados en código (`kindlehome.koplugin/lib/{config,logger}.lua`, `ui/dashboard.lua`, `main.lua`); **pendiente verificación en Kindle real** (objetivo) y registro en ledger antes de avanzar a Fase 2.
- **Tier de método:** `Standard` (mhproject) — `PLAN.md` + `AGENTS.md` + `README.md`, fases con dependencias, verificación por fase y registro de desviaciones/ledger.
- **Plataforma objetivo:** **Kindle con KOReader (e-ink)**. El plugin está enfocado a Kindle; **no** se orienta ni garantiza para KOReader en PC/desktop.
- **Entorno de desarrollo:** KOReader en Linux desktop puede usarse solo como entorno auxiliar de iteración rápida (sin ser objetivo). La referencia de comportamiento, UX y validación final es **Kindle real**.
- **Idioma UI (MVP):** inglés. Usar `_()` donde aplique; fallback manual permitido si no se compila `l10n`.
- **Rutas KOReader (referencia):**
  - Kindle (objetivo): `/mnt/us/koreader/plugins/kindlehome.koplugin/` (requiere reinicio de KOReader)
  - Desktop auxiliar (opcional, solo dev): `~/.config/koreader/plugins/kindlehome.koplugin/`
  - Settings: `<DataStorage:getSettingsDir()>/kindlehome.lua` (vía `LuaSettings`)
  - Cache: `<DataStorage:getDataDir()>/cache/kindlehome/`
- **Datos persistidos (default, visible al usuario):** `documents/KindleHome/` dentro del home de documentos de KOReader/Kindle.
  - Artículos HN: `documents/KindleHome/articles/hn/`
  - Artículos RSS: `documents/KindleHome/articles/rss/<feed_slug>/`
  - Digest: `documents/KindleHome/digest/YYYY-MM-DD.md` y `.html`
  - Alternativa documentada (si se decide ocultar del explorador): `<DataDir>/news/kindlehome/` (configurable).
- **Lectura por defecto:** overlay `ScrollHtmlWidget` con retorno al dashboard. “Abrir en lector” (`ReaderUI:showReader`) es opcional y debe aislarse (no acoplar al flujo base).
- **Red:** solo bajo demanda o según política de refresh; siempre cache-first con fallback a caché válida/obsoleta + mensaje claro.

## 2) Decisiones cerradas y supuestos

### Cerradas (usuario)
- **HN vía `hnmd`**: `GET {base_url}/top` (default `https://hnmd.miguehm.com`).
- **Auth:** `Authorization: Bearer <hnmd_api_key>` configurable **desde menú UI y edición manual** de `settings/kindlehome.lua` (`hnmd_api_key`).
- **Manejo requerido:** `200`, `401`, `503 warming_up`, errores de red/JSON inválido.

### Supuestos operativos
- `hnmd` entrega `markdown` por item (cuando `status == ok`) y `hn_url` siempre presente; `url` puede ser `null` (Ask HN).
- KOReader expone utilidades estándar: `socketutil`, `dkjson/json`, `LuaSettings`, `NetworkMgr`, `UIManager`, `ScrollHtmlWidget`, `util`, `datetime`, `DataStorage`.
- Se prioriza robustez en e-ink: HTML/CSS simple, timeouts cortos, límites de bytes, sin trabajos pesados bloqueantes.

### Fuera de alcance (MVP, salvo fase opcional)
- Extracción full-text avanzada de artículos externos (RSS/web) como comportamiento garantizado.
- Imágenes remotas embebidas/descargadas en artículos.
- Screensaver userpatch soportado oficialmente.
- Sincronización multi-dispositivo o cifrado de secretos.

## 3) Contratos transversales (obligatorios)

### 3.1 Configuración (`lib/config.lua`, `LuaSettings`)
- **Archivo:** `settings/kindlehome.lua`
- **Reglas:** defaults centralizados, getters/setters tipados, validación y saneamiento al cargar (valores fuera de rango → default), escritura explícita (`flush` cuando aplique).
- **Claves mínimas (MVP):**
  - General/UI: `refresh_on_open` (bool), `show_battery` (bool), `show_network` (bool)
  - Rutas: `storage_mode` (`documents|datadir`), `documents_subdir` (`KindleHome`)
  - Clima: `weather_enabled`, `weather_lat`, `weather_lon`, `weather_place_name`, `weather_ttl_minutes`
  - HN/hnmd: `hnmd_enabled`, `hnmd_base_url`, `hnmd_api_key`, `hnmd_max_items` (1–20), `hnmd_ttl_minutes`
  - RSS: `rss_enabled`, `rss_ttl_minutes`, `rss_feeds[]` (`{id,name,url,enabled,max_items,max_age_hours?}`)
  - Red: `http_timeout_s`, `http_max_bytes`, `refresh_budget_s` (presupuesto total por actualización)
- **Seguridad:** `hnmd_api_key` se guarda en texto plano local (limitación KOReader). No loguear nunca; en UI mostrar enmascarada con opción de revelar/editar. Validar `hnmd_base_url` con esquema `https://` por defecto.

### 3.2 Rutas y persistencia (`lib/paths.lua`)
- Resolver rutas base desde config + `DataStorage` y crear directorios bajo demanda.
- Normalizar nombres/slug de archivos (evitar caracteres inválidos, colisiones por id/fecha/hash corto).
- Todas las escrituras de contenido/cache deben ser **atómicas** (tmp + rename) para evitar corrupción parcial.

### 3.3 Cache (`lib/cache.lua`)
- Ubicación: `<DataDir>/cache/kindlehome/*.json`
- Namespaces sugeridos: `weather.json`, `hnmd.json`, `rss.json`, `dashboard_meta.json`
- **Envelope común:**
  - `schema_version` (int), `fetched_at` (epoch), `ttl_seconds` (int), `source` (string), `status` (`ok|stale|error`), `error` (opcional), `payload` (objeto)
- **Política:** cache-first al abrir; refresh si TTL vencido y hay red, o por acción explícita. Si fetch falla, conservar último payload válido y marcar `stale/error` con mensaje corto.
- **Recuperación:** JSON corrupto o `schema_version` incompatible → mover/ignorar archivo y regenerar (sin crashear).

### 3.4 HTTP (`lib/http.lua`) y red
- GET texto/JSON con `socketutil` timeouts, límite de bytes, `User-Agent`, y resultado tipado `{ok,status,body,headers?,error_kind}`.
- **Error kinds mínimos:** `timeout`, `network`, `http_401`, `http_503`, `http_other`, `parse`, `too_large`.
- Retries: solo para fallos transitorios de red/timeout (máx. 1 reintento corto) y **nunca** en bucle para `401`.
- Respetar presupuesto global de actualización (`refresh_budget_s`) y fetch secuencial por fuente para no congelar UI.

### 3.5 Logging y UX de errores (`lib/logger.lua` + UI)
- Log acotado y estructurado por módulo/evento (`http_fetch`, `cache_load`, `refresh_done`, etc.) sin secretos ni payloads sensibles.
- Usuario final: mensajes breves y accionables (“Offline, showing cached data”, “Invalid API key in Settings”, “hnmd server is starting, try again in a few minutes”).

### 3.6 Modelos de dominio normalizados (internos)
- `DashboardState`: hora, batería, red, clima, hn, rss, errores/resumen de refresh, timestamps.
- `WeatherView`: actual, min/max, código WMO+texto, `place_name`, `observed_at/fetched_at`, `is_stale`.
- `HnItemView`: `id`, `rank`, `type`, `title`, `hn_url`, `url?`, `by`, `score`, `descendants`, `published_at`, `domain`, `markdown`, `status`, `error?`, `scraped_at`.
- `FeedItemView`: `feed_id`, `feed_name`, `item_id` estable, `title`, `link?`, `published_ts?`, `author?`, `summary_md`, `source_url`.
- `ArticleDoc`: metadatos + cuerpo MD + HTML renderizado + rutas de archivo.

## 4) Arquitectura objetivo (estructura de archivos)

> Estructura lógica objetivo del plugin (autocontenible para copiar a KOReader). Ajustes menores permitidos si se registra en desviaciones.

```text
repo/
  PLAN.md
  AGENTS.md                    # crear (invariantes, comandos/gates, no loguear secretos)
  README.md                    # crear (instalación dev/Kindle, config, rutas, troubleshooting)
  CHANGELOG.md                 # cuando exista primera entrega funcional
  LICENSE                      # si aplica
  THIRD_PARTY_NOTICES.md       # si se copian/adaptan fuentes (p.ej. parsers de newsdownloader)

  kindlehome.koplugin/
    _meta.lua
    main.lua                   # bootstrap, menú, dispatcher, orquestación
    lib/
      config.lua
      paths.lua
      cache.lua
      http.lua
      logger.lua
      wmo.lua
      geocoding.lua
      weather.lua
      hnmd.lua
      digest.lua
      rss/
        parser.lua
        normalize.lua
        vendor/
          dateparser.lua
          xml.lua
          handler.lua
          LICENSE_NOTES
      render/
        md_to_html.lua
        dashboard_html.lua
    ui/
      dashboard.lua
      article_view.lua
      menus.lua                # ajustes/configuración (incl. HN y feeds)
      actions.lua              # acciones internas y ruteo (fallback sin deep-links HTML)
    assets/                    # solo si hay recursos reales
```

**Notas de arquitectura**
- Separar `fetch/parse/normalize` de `render/persist` para testear lógica en desktop.
- `ui/actions.lua` centraliza acciones `refresh`, `open_hn`, `open_rss`, `open_digest`, `close`, con IDs estables (evitar depender exclusivamente de enlaces HTML clicables).
- Copias desde `newsdownloader.koplugin`: preferir copia controlada con atribución/licencia explícita; evitar `dofile` a rutas externas frágiles salvo prototipo temporal documentado.

## 5) Flujo de implementación corregido (orden y dependencias)

**Secuencia recomendada (MVP):**
1. **Fase 0** — Scaffold y panel mínimo
2. **Fase 1** — Dashboard offline (estado local dispositivo)
3. **Fase 2** — Base transversal (config/paths/cache/http/logger) + contratos
4. **Fase 3** — Renderer, navegación y persistencia de lectura (prerrequisito compartido)
5. **Fase 4** — Clima (Open-Meteo + geocoding)
6. **Fase 5** — Hacker News vía `hnmd` (datos, caché, UI, lectura con markdown)
7. **Fase 6** — RSS/Atom (parse, normalización, caché, lectura)
8. **Fase 7** — Digest y pulido de lectura
9. **Fase 8** — Ajustes completos, gestos y automatización
10. **Fase 9** — Endurecimiento, pruebas dispositivo y empaquetado

**Cambio clave respecto al plan anterior:** la lectura de artículos (overlay/persistencia/renderer/ruteo) se resuelve en **Fase 3** antes de integrar fuentes de contenido, eliminando la dependencia cruzada HN↔RSS↔MD.

## 6) Fases detalladas (con dependencias y verificación)

### Fase 0 — Scaffold y panel mínimo (sin red)
**Depende de:** —
- [x] **0.1** Crear estructura base `kindlehome.koplugin/` (`lib/`, `ui/`, `lib/rss/vendor/`, `lib/render/`) sin archivos basura.
- [x] **0.2** `_meta.lua`: `fullname`, `description` (EN, preparado para `_()`).
- [x] **0.3** `main.lua`: `WidgetContainer` (`name="kindlehome"`), registro en menú principal.
- [x] **0.4** Dispatcher: acción `kindlehome_show_dashboard` + handler `onKindlehomeShowDashboard`.
- [x] **0.5** `ui/dashboard.lua`: render HTML estático en `ScrollHtmlWidget` full-screen (acciones mínimas: Refresh stub, Close).
- [x] **0.6** Documentar en `README.md` (borrador) instalación dev/Kindle y reinicio requerido.

**Criterio de salida:** plugin carga, aparece en menú y abre/cierra dashboard sin errores en **Kindle (objetivo)**; smoke test en desktop auxiliar opcional.  
**Verificación (ledger):** en Kindle real (referencia) validar carga, abrir/cerrar 3 veces, ejecutar acción Dispatcher y revisar log sin stack traces; desktop solo como apoyo opcional.

### Fase 1 — Dashboard offline (hora, fecha, batería, red)
**Depende de:** Fase 0
- [x] **1.1** `lib/config.lua` inicial con defaults y `LuaSettings` (`settings/kindlehome.lua`).
- [x] **1.2** Encabezado con fecha/hora legible en inglés.
- [x] **1.3** Estado de batería (`getCapacity`, `isCharging`) con fallback seguro si no disponible (comportamiento de referencia en Kindle).
- [x] **1.4** Estado de red (`NetworkMgr:isConnected`) y SSID si es seguro/posible en Kindle; fallback seguro en otros entornos.
- [x] **1.5** Contrato de refresco de vista: función única `refresh()` que reconstruye estado/HTML y reemplaza/reabre widget de forma controlada (documentar comportamiento de scroll).
- [x] **1.6** `lib/logger.lua` básico (niveles/eventos) sin datos sensibles.

**Criterio de salida:** dashboard muestra datos locales y se refresca sin crashear en **Kindle (objetivo)**.  
**Verificación:** en Kindle real, cambiar WiFi/energía cuando aplique, refrescar manualmente y confirmar actualización visible; desktop auxiliar opcional solo para iteración rápida. *(Implementación en repo completada; verificación en dispositivo pendiente.)*

### Fase 2 — Base transversal (config/paths/cache/http) y contratos
**Depende de:** Fase 1
- [ ] **2.1** `lib/paths.lua`: resolución de rutas base, creación de directorios y helpers de nombres seguros.
- [ ] **2.2** `lib/http.lua`: GET con timeout, límite de bytes, UA, parse JSON opcional y errores tipados.
- [ ] **2.3** `lib/cache.lua`: envelope versionado, TTL, lectura tolerante, escritura atómica, recuperación ante corrupción.
- [ ] **2.4** Ampliar `config.lua`: validación/saneamiento de claves, defaults completos MVP, helpers para TTL/presupuestos.
- [ ] **2.5** Política común de refresh: cache-first, stale fallback, presupuesto por ciclo y protección contra reentrada.
- [ ] **2.6** `AGENTS.md` (borrador): invariantes (timeouts/límites obligatorios, no loguear `hnmd_api_key`, rutas canónicas, no dead code).

**Criterio de salida:** módulos transversales reutilizables con manejo de error/corrupción definido.  
**Verificación:** simular timeout, HTTP error, JSON inválido y caché corrupta (archivo truncado) sin crash.

### Fase 3 — Renderer, navegación y persistencia de lectura (prerrequisito)
**Depende de:** Fase 2
- [ ] **3.1** `lib/render/md_to_html.lua`: conversor MD simple → HTML seguro (escape, h1–h3, p, ul/ol/li, a, strong/em, code/pre, hr) + CSS inline e-ink.
- [ ] **3.2** `ui/article_view.lua`: overlay de lectura reutilizable desde MD/HTML generado; cabecera de metadatos y cierre a dashboard.
- [ ] **3.3** Persistencia de artículos: guardar `.md` y `.html` con metadatos mínimos (frontmatter o bloque inicial) en rutas canónicas.
- [ ] **3.4** `ui/actions.lua`: ruteo de acciones internas (`open_hn:<id>`, `open_rss:<feed_id>:<item_id>`, `open_digest:<date>`), con **fallback sin deep-links HTML** (lista/botones Lua) si el widget no expone taps navegables.
- [ ] **3.5** Contrato de “abrir en lector” (opcional, desactivado por defecto): wrapper aislado a `ReaderUI:showReader` con nota de comportamiento de retorno.
- [ ] **3.6** Plantilla base de errores/estados vacíos en lectura (“content unavailable”, “no markdown”, “corrupted file”).

**Criterio de salida:** se puede renderizar y abrir un artículo de prueba persistido (MD→HTML) y volver al dashboard por ruta interna estable.  
**Verificación:** abrir/cerrar artículos de prueba, validar escape HTML, enlaces/encabezados básicos y fallback de navegación.

### Fase 4 — Clima (Open-Meteo + geocoding)
**Depende de:** Fases 2, 3 (para render/UI común) y 1
- [ ] **4.1** Config UI/campos: lat/lon manual y nombre de lugar.
- [ ] **4.2** `lib/wmo.lua`: mapa WMO → texto EN.
- [ ] **4.3** `lib/geocoding.lua` (recomendado): búsqueda por nombre → lat/lon/place.
- [ ] **4.4** `lib/weather.lua`: fetch forecast Open-Meteo, normalización `WeatherView`, guardado en `cache/weather.json`.
- [ ] **4.5** Integración en dashboard: actual + min/max; stale/cache timestamp; estado “configure location”.
- [ ] **4.6** UX sin red: prompt “turn on WiFi and refresh” (`NetworkMgr:promptWifiOn`) con callback y fallback a caché.

**Criterio de salida:** clima funciona online, degrada correctamente offline y respeta TTL/cache.  
**Verificación:** con/sin ubicación, con/sin red, caché vigente y expirada.

### Fase 5 — Hacker News vía `hnmd`
**Depende de:** Fases 2, 3, 4 (integración visual en dashboard)
- [ ] **5.1** Extender config: `hnmd_enabled`, `hnmd_base_url`, `hnmd_api_key`, `hnmd_max_items`, `hnmd_ttl_minutes`.
- [ ] **5.2** UI ajustes HN: editar base URL, API key (enmascarada), max items, toggle; documentar edición manual en `settings/kindlehome.lua`.
- [ ] **5.3** `lib/hnmd.lua`: GET `{base}/top` con `Authorization: Bearer` si aplica, parse/validación de respuesta (`generated_at,next_refresh_at,refresh_interval,count,items,last_refresh_error?`).
- [ ] **5.4** Normalizar `NewsItem` → `HnItemView` y limitar por `hnmd_max_items` (orden `rank`).
- [ ] **5.5** Cache `cache/hnmd.json`: snapshot + estado fetch, TTL configurable, stale fallback.
- [ ] **5.6** Manejo HTTP/estado:
  - `200`: render + cache ok.
  - `503 warming_up`: mensaje y uso de caché si existe.
  - `401`: banner accionable a Settings, sin reintentos automáticos.
  - red/timeout/parse/otros: mensaje breve + caché si existe.
- [ ] **5.7** Dashboard sección HN: lista con rank, título, score/comentarios/autor/dominio; marcar `status!=ok` o markdown vacío.
- [ ] **5.8** Lectura de artículo HN: usar `article_view` + `md_to_html` con markdown del servidor; guardar `.md/.html` en `articles/hn/`.
- [ ] **5.9** Caso `url == null` (Ask HN): no intentar fetch externo; mostrar solo contenido `hnmd`.
- [ ] **5.10** (Opcional MVP+) abrir URL externa en overlay con descarga limitada/timeout y error claro; si se pospone, documentar como no soportado.

**Criterio de salida:** HN lista y abre artículos `markdown` desde `hnmd` con cache y manejo correcto de `401/503`.  
**Verificación:** 200, 401, 503 warming_up, sin red con caché, item `status:error`/sin markdown, Ask HN (`url=null`).

### Fase 6 — RSS/Atom genéricos
**Depende de:** Fases 2, 3, 4 (integración visual/dashboard)
- [ ] **6.1** Importar/adaptar parsers (`dateparser`, `xml`, `handler`) en `lib/rss/vendor/` con atribución/licencia en `THIRD_PARTY_NOTICES.md` o `LICENSE_NOTES`.
- [ ] **6.2** `lib/rss/parser.lua`: parse RSS/Atom a estructura uniforme (`title, link, summary/content, published_ts, author`).
- [ ] **6.3** `lib/rss/normalize.lua`: HTML→texto/MD seguro (resumen MVP) usando utilidades KOReader + limpieza básica.
- [ ] **6.4** Config de feeds: CRUD básico en `ui/menus.lua` (añadir/listar/editar/eliminar, enabled, max_items) + persistencia.
- [ ] **6.5** Fetch secuencial con presupuesto/timeouts/límites por feed y por ciclo.
- [ ] **6.6** Cache `cache/rss.json` (por feed + agregada) con TTL y manejo de stale.
- [ ] **6.7** Dashboard sección RSS (lista plana o agrupada, decisión documentada) con acciones internas estables.
- [ ] **6.8** Persistencia y lectura de artículo RSS en overlay (`.md/.html`) usando renderer común.
- [ ] **6.9** (Opcional, Fase 9) extracción full-text (`reduceHTML`/htmlparser) como mejora experimental.

**Criterio de salida:** al menos un feed RSS funciona end-to-end (config, fetch, cache, listado, lectura, persistencia).  
**Verificación:** feed válido, feed inválido, timeout, HTML sucio, sin red con caché.

### Fase 7 — Digest y pulido de lectura
**Depende de:** Fases 4, 5, 6
- [ ] **7.1** `lib/digest.lua`: modelo de portada diaria (hora, clima, top HN, titulares RSS) + render MD/HTML.
- [ ] **7.2** Persistir `digest/YYYY-MM-DD.md/.html` y exponer “Open latest digest”.
- [ ] **7.3** Unificar estilos HTML/CSS para MuPDF (simple, legible en e-ink) entre dashboard/artículos/digest.
- [ ] **7.4** Mejoras de lectura: metadatos consistentes, estados vacíos, navegación de retorno predecible.
- [ ] **7.5** (Opcional) acción “Abrir en lector” para archivos generados, detrás de flag/config.

**Criterio de salida:** digest diario generado/abrible y lectura consistente entre fuentes.  
**Verificación:** generar digest con datos parciales (p.ej. solo clima o solo HN), reabrir, revisar render en desktop.

### Fase 8 — Ajustes completos, gestos y automatización
**Depende de:** Fases 4–7
- [ ] **8.1** Menú de ajustes completo: clima, HN, feeds, rutas, TTLs, refresh policy, toggles de secciones.
- [ ] **8.2** Dispatcher/documentación para gesto y Profiles (abrir al inicio / al despertar) con comportamiento seguro.
- [ ] **8.3** Política de refresh al abrir: cache-first + refresco condicionado por TTL/red/presupuesto; indicador de progreso breve.
- [ ] **8.4** Centralizar mensajes de error/estado en UI (sin stack traces, sin secretos).
- [ ] **8.5** Endurecer límites: tamaño máximo de payload, número de items/feeds por ciclo, timeout global de actualización.

**Criterio de salida:** flujo diario completo (abrir panel → ver estado → refrescar → leer) usable y predecible.  
**Verificación:** apertura automática/manual, offline/online, cancelación lógica por presupuesto (si aplica), reentrada de refresh.

### Fase 9 — Endurecimiento, validación en dispositivo y empaquetado
**Depende de:** Fase 8
- [ ] **9.1** Matriz de pruebas desktop + Kindle real (sin WiFi, WiFi inestable, 401/503, feeds rotos, lat/lon inválida, caché corrupta, settings incompletos).
- [ ] **9.2** Revisar performance percibida en Kindle (tiempos de fetch/parse/render) y ajustar budgets/TTLs/defaults.
- [ ] **9.3** Revisión de seguridad/privacidad: enmascarado de key, no logs sensibles, documentación de almacenamiento local.
- [ ] **9.4** Documentación final: `README.md`, `CHANGELOG.md`, troubleshooting, configuración `hnmd_api_key` (UI y archivo), rutas de datos.
- [ ] **9.5** Empaquetado: zip instalable de `kindlehome.koplugin`, checklist de release, versión en `_meta.lua`.
- [ ] **9.6** (Opcional) extracción full-text RSS, fallback HN alternativo, i18n completa, userpatch/screensaver experimental.

**Criterio de salida:** MVP instalable, documentado y validado en dispositivo objetivo con fallos comunes controlados.  
**Verificación:** ejecución completa de matriz de pruebas y registro en ledger.

## 7) Matriz de verificación mínima (por fase)

> **Referencia:** la validación objetivo es **Kindle real** (e-ink/KOReader). Pruebas en desktop/PC son auxiliares y no sustituyen la verificación en Kindle.

- **F0–F1 (UI/local):** en Kindle: carga plugin, navegación básica, refresh, sin errores en log (desktop auxiliar opcional).
- **F2 (transversal):** timeout, HTTP 401/503/500 simulado o forzado, JSON inválido, caché corrupta, escritura atómica.
- **F3 (lectura):** render MD básico, escape HTML, persistencia `.md/.html`, apertura/cierre overlay, fallback navegación.
- **F4 (clima):** ubicación válida/inválida, geocoding OK/fail, online/offline, TTL expirado.
- **F5 (hnmd):** 200, 401, 503 `warming_up`, red caída, item sin markdown/error, Ask HN `url=null`.
- **F6 (RSS):** feed RSS/Atom válido, feed inválido, contenido HTML, límite por feed, cache/stale.
- **F7–F8 (integración):** digest parcial/completo, refresh al abrir, gestos/profiles, reentrada.
- **F9 (dispositivo):** smoke + regresión en **Kindle real** y tiempos aceptables (obligatorio para cierre MVP).

## 8) Riesgos, mitigaciones y decisiones abiertas

### Riesgos (con mitigación)
- **UI bloqueada durante red/parse:** fetch secuencial, timeouts cortos, límites de bytes, presupuesto global, refresh manual explícito.
- **Navegación HTML limitada en widgets KOReader:** acciones internas Lua como fuente de verdad; deep-links HTML solo como mejora si se confirma soporte.
- **Render MuPDF/CSS limitado:** HTML simple, sin dependencias visuales complejas, estilos inline mínimos y probados.
- **Dependencia externa `hnmd`:** cache-first, stale fallback, mensajes específicos por estado, posibilidad futura de fallback alternativo.
- **Persistencia de API key en texto plano:** enmascarar en UI, no loguear, documentar riesgo y rotación.
- **Datos/caché corruptos o versión incompatible:** envelope versionado + recuperación automática (reset controlado).
- **Código copiado de terceros (parsers):** copia controlada, trazabilidad de origen y avisos de licencia.

### Decisiones abiertas (registrar al resolver)
- [ ] Ruta por defecto final: `documents/KindleHome` vs `<DataDir>/news/kindlehome` (priorizar visibilidad o limpieza del explorador).
- [ ] Mecanismo de navegación a artículos: solo acciones Lua vs híbrido (Lua + enlaces HTML) tras prueba en `ScrollHtmlWidget`.
- [ ] Política exacta de refresh automático al abrir (solo stale, solo WiFi, máximo por intervalo).
- [ ] ¿Habilitar “Abrir en lector” en MVP o dejarlo para post-MVP?

## 9) Registro de desviaciones / deuda (plantilla)

> Registrar toda divergencia del plan con fecha, motivo, impacto y estado. No borrar entradas; cerrar como resuelta o diferida.

| Fecha | Fase/Tarea | Desviación | Motivo | Impacto | Estado | Resolución / seguimiento |
|---|---|---|---|---|---|---|
| YYYY-MM-DD | F0/0.x | (ej.) Se cambió ruta de cache | (motivo) | (bajo/medio/alto) | ⏸ diferida / ✔ resuelta | (acción tomada o pendiente) |

## 10) Ledger de verificación (plantilla)

> Registrar cada ejecución relevante de verificación (por fase, regresión o pre-release).

| Fecha | Fase | Entorno | Qué se verificó | Resultado | Evidencia / notas | Flakes / pendientes |
|---|---|---|---|---|---|---|
| YYYY-MM-DD | F0 | KOReader desktop Linux / Kindle FW ... | Carga plugin, abrir/cerrar dashboard | PASS/FAIL | log, screenshot, pasos | (si aplica) |

## 11) Criterios de aceptación del MVP (definición de terminado)

- El plugin está enfocado y validado para **Kindle (KOReader, e-ink)**; no se considera objetivo de soporte PC/desktop.
- Dashboard abre desde menú/gesto en Kindle y muestra hora/fecha + estado básico + secciones disponibles.
- Clima, HN (`hnmd`) y RSS funcionan con **cache-first**, estados de error manejados y sin crashes offline.
- HN soporta `hnmd_api_key` por UI y por `settings/kindlehome.lua`, con manejo correcto de `200/401/503 warming_up`.
- Artículos HN/RSS y digest se pueden renderizar en overlay, persistir en `.md/.html` y reabrir.
- Configuración y rutas están documentadas; no se registran secretos en logs; caché corrupta se recupera automáticamente.
- Existe verificación registrada por fases críticas y **smoke/regresión en Kindle real** (obligatorio).