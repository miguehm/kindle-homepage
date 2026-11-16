# Plan de implementación — Kindle Home (plugin KOReader)

> Objetivo: plugin KOReader (`kindlehome.koplugin`) tipo “homepage” para Kindle (KUAL + KOReader) con reloj/fecha, estado del dispositivo, clima (Open-Meteo) y **Hacker News vía `hnmd`** (`https://hnmd.miguehm.com/top`); lectura en Markdown (persistencia `.md` + render HTML en crengine).  
> Fuente técnica base: investigación 2026-11-15 sobre KOReader v2026.07.1 en `/usr/lib/koreader`.  
> Este documento es el **contrato de implementación** (fases, dependencias, criterios, riesgos y registros). **No iniciar implementación** fuera de lo que la fase activa autorice.

## 1) Estado, alcance y convenciones

- **Estado del repo:** F0–F7 implementadas; **F8 (8.1–8.5) preparada**, **F9 (rediseño UI/fullscreen)** y **F10 (migración a artículos Markdown descargados, 10.1–10.9) implementadas en repo** (`check_lua51`, `check_invariants`, `smoke_ui` con 8 smokes PASS; docs/`CHANGELOG.md`). **Hotfix 0.3.1** aplicado: `Shell` cablea `dialog`/`show_parent` al widget de nivel superior para que `UIManager:setDirty` repinte el cuerpo al desplazarse (validado en Kindle PW5: navegación por flick/tap OK). Refactor del cuerpo a UI nativa (dashboard + fallback de artículos) planificado como siguiente fase. **Pendiente verificación en Kindle real** (matriz F1–F10, legibilidad/targets, fullscreen/rotación, descargas reales, performance, smoke desde zip) para cierre formal. **8.6 diferido (post-MVP)**.
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
  - Digest: `documents/KindleHome/digest/YYYY-MM-DD.md` y `.html`
  - Alternativa documentada (si se decide ocultar del explorador): `<DataDir>/news/kindlehome/` (configurable).
- **Lectura por defecto:** overlay `ScrollHtmlWidget` con retorno al dashboard. “Abrir en lector” (`ReaderUI:showReader`) es opcional y debe aislarse (no acoplar al flujo base).
- **Red:** solo bajo demanda o según política de refresh; siempre cache-first con fallback a caché válida/obsoleta + mensaje claro.
- **Soporte de contenido:** **solo Hacker News vía `hnmd`**. No hay soporte RSS/Atom en el MVP.

## 2) Decisiones cerradas y supuestos

### Cerradas (usuario)
- **HN vía `hnmd`**: `GET {base_url}/top` (default `https://hnmd.miguehm.com`).
- **Auth:** `Authorization: Bearer <hnmd_api_key>` configurable **desde menú UI y edición manual** de `settings/kindlehome.lua` (`hnmd_api_key`).
- **Manejo requerido:** `200`, `401`, `503 warming_up`, errores de red/JSON inválido.
- **Sin RSS/Atom:** retirado del alcance (2026-11-15).

### Supuestos operativos
- `hnmd` expone `/v1/top` como índice **sin cuerpos** y `/v1/articles/{id}.md` por artículo (Bearer en ambos); `content_url` llega origin-absolute (`/v1/...`), `content_length` permite verificar la descarga y `content_status` (`ok|no_content|warming_up|error`) indica si hay cuerpo. `url` puede ser `null` (Ask HN).
- KOReader expone utilidades estándar: `socketutil`, `dkjson/json`, `LuaSettings`, `NetworkMgr`, `UIManager`, `ScrollHtmlWidget`, `util`, `datetime`, `DataStorage`.
- Se prioriza robustez en e-ink: HTML/CSS simple, timeouts cortos, límites de bytes, sin trabajos pesados bloqueantes.

### Fuera de alcance (MVP, salvo fase opcional)
- **RSS/Atom y feeds externos.**
- Extracción full-text avanzada de artículos externos (web) como comportamiento garantizado.
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
  - HN/hnmd: `hnmd_enabled`, `hnmd_base_url` (default `https://hnmd.miguehm.com/v1`; un host sin path recibe `/v1`), `hnmd_api_key`, `hnmd_max_items` (1–20), `hnmd_ttl_minutes`, `index_max_bytes` (32–256 KiB, default 128 KiB), `article_max_bytes` (16 KiB–1 MiB, default 512 KiB)
  - Red: `http_timeout_s`, `http_max_bytes` (JSON de clima/otros), `refresh_budget_s` (presupuesto total por actualización)
- **Seguridad:** `hnmd_api_key` se guarda en texto plano local (limitación KOReader). No loguear nunca; en UI mostrar enmascarada con opción de revelar/editar. Validar `hnmd_base_url` con esquema `https://` por defecto.

### 3.2 Rutas y persistencia (`lib/paths.lua`)
- Resolver rutas base desde config + `DataStorage` y crear directorios bajo demanda.
- Normalizar nombres/slug de archivos (evitar caracteres inválidos, colisiones por id/fecha/hash corto).
- Todas las escrituras de contenido/cache deben ser **atómicas** (tmp + rename) para evitar corrupción parcial.

### 3.3 Cache (`lib/cache.lua`)
- Ubicación: `<DataDir>/cache/kindlehome/*.json`
- Namespaces sugeridos: `weather.json`, `hnmd.json`, `dashboard_meta.json`
- **Envelope común:**
  - `schema_version` (int), `fetched_at` (epoch), `ttl_seconds` (int), `source` (string), `status` (`ok|stale|error`), `error` (opcional), `payload` (objeto)
- **Política:** cache-first al abrir; refresh si TTL vencido y hay red, o por acción explícita. Si fetch falla, conservar último payload válido y marcar `stale/error` con mensaje corto.
- **Recuperación:** JSON corrupto o `schema_version` incompatible → mover/ignorar archivo y regenerar (sin crashear).

### 3.4 HTTP (`lib/http.lua`) y red
- `Http.get`/`get_json` (pequeños JSON en RAM: `/v1/top`, clima) y `Http.get_to_file` (cuerpos de artículo: streaming a `.tmp`, `Content-Length` verificado, `os.rename` atómico, `.tmp` borrado en fallo) con `socketutil` timeouts, límites de bytes, `User-Agent` y resultado tipado `{ok,status,body|bytes,headers?,error_kind}`.
- **Error kinds mínimos:** `timeout`, `network`, `http_401`, `http_404`, `http_503`, `http_other`, `parse`, `too_large`, `incomplete`.
- Retries: solo para fallos transitorios de red/timeout (máx. 1 reintento corto) y **nunca** en bucle para `401`.
- Respetar presupuesto global de actualización (`refresh_budget_s`) y fetch secuencial por fuente para no congelar UI.

### 3.5 Logging y UX de errores (`lib/logger.lua` + UI)
- Log acotado y estructurado por módulo/evento (`http_fetch`, `cache_load`, `refresh_done`, etc.) sin secretos ni payloads sensibles.
- Usuario final: mensajes breves y accionables (“Offline, showing cached data”, “Invalid API key in Settings”, “hnmd server is starting, try again in a few minutes”).

### 3.6 Modelos de dominio normalizados (internos)
- `DashboardState`: hora, batería, red, clima, hn, errores/resumen de refresh, timestamps.
- `WeatherView`: actual, min/max, código WMO+texto, `place_name`, `observed_at/fetched_at`, `is_stale`.
- `HnItemView` (índice, sin cuerpo): `id`, `rank`, `type`, `title`, `hn_url`, `url?`, `by`, `score`, `descendants`, `published_at`, `domain`, `content_status` (`ok|no_content|warming_up|error`), `content_error?`, `content_url`, `content_type`, `content_length`, `updated_at`.
- `ArticleDoc`: metadatos + `.md` descargado (canónico) + `.md.html` derivado + rutas de archivo.

## 4) Arquitectura objetivo (estructura de archivos)

> Estructura lógica objetivo del plugin (autocontenible para copiar a KOReader). Ajustes menores permitidos si se registra en desviaciones.

```text
repo/
  PLAN.md
  AGENTS.md
  README.md
  CHANGELOG.md                 # cuando exista primera entrega funcional
  LICENSE                      # si aplica

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
      render/
        md_to_html.lua
        dashboard_html.lua
    ui/
      dashboard.lua
      article_view.lua
      menus.lua                # ajustes/configuración (incl. HN)
      actions.lua              # acciones internas y ruteo (fallback sin deep-links HTML)
    assets/                    # solo si hay recursos reales
```

**Notas de arquitectura**
- Separar `fetch/parse/normalize` de `render/persist` para testear lógica en desktop.
- `ui/actions.lua` centraliza acciones `refresh`, `open_hn`, `open_digest`, `close`, con IDs estables (evitar depender exclusivamente de enlaces HTML clicables).

## 5) Flujo de implementación corregido (orden y dependencias)

**Secuencia recomendada (MVP):**
1. **Fase 0** — Scaffold y panel mínimo
2. **Fase 1** — Dashboard offline (estado local dispositivo)
3. **Fase 2** — Base transversal (config/paths/cache/http/logger) + contratos
4. **Fase 3** — Renderer, navegación y persistencia de lectura (prerrequisito compartido)
5. **Fase 4** — Clima (Open-Meteo + geocoding)
6. **Fase 5** — Hacker News vía `hnmd` (datos, caché, UI, lectura con markdown)
7. **Fase 6** — Digest y pulido de lectura
8. **Fase 7** — Ajustes completos, gestos y automatización
9. **Fase 8** — Endurecimiento, pruebas dispositivo y empaquetado

**Cambio clave:** se retira RSS/Atom; la lectura (overlay/persistencia/renderer/ruteo) se resuelve en **Fase 3** antes de integrar fuentes de contenido.

## 6) Fases detalladas (con dependencias y verificación)

### Fase 0 — Scaffold y panel mínimo (sin red)
**Depende de:** —
- [x] **0.1** Crear estructura base `kindlehome.koplugin/` (`lib/`, `ui/`, `lib/render/`) sin archivos basura.
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
**Depende de:** Fase 1 *(gate: verificación F1 en Kindle real y ledger pendientes)*
- [x] **2.1** `lib/paths.lua`: resolución de rutas base, creación de directorios y helpers de nombres seguros.
- [x] **2.2** `lib/http.lua`: GET con timeout, límite de bytes, UA, parse JSON opcional y errores tipados.
- [x] **2.3** `lib/cache.lua`: envelope versionado, TTL, lectura tolerante, escritura atómica, recuperación ante corrupción.
- [x] **2.4** Ampliar `config.lua`: validación/saneamiento de claves, defaults completos MVP, helpers para TTL/presupuestos.
- [x] **2.5** Política común de refresh: cache-first, stale fallback, presupuesto por ciclo y protección contra reentrada (`lib/refresh.lua`).
- [x] **2.6** `AGENTS.md` (borrador): invariantes (timeouts/límites obligatorios, no loguear `hnmd_api_key`, rutas canónicas, no dead code).

> **Nota (2026-11-15):** módulos transversales implementados en repo; verificación de casos F2 y cierre formal pendientes de registrar en ledger (desktop auxiliar para simulación + Kindle cuando aplique). No avanzar a F3 sin cumplir gate de F1.

**Criterio de salida:** módulos transversales reutilizables con manejo de error/corrupción definido.  
**Verificación:** simular timeout, HTTP error, JSON inválido y caché corrupta (archivo truncado) sin crash.

### Fase 3 — Renderer, navegación y persistencia de lectura (prerrequisito)
**Depende de:** Fase 2 *(gate F1 en Kindle y verificación/cierre formal F2 siguen pendientes en ledger; implementación F3 avanzada en repo sin cerrar gates previos)*
- [x] **3.1** `lib/render/md_to_html.lua`: conversor MD simple → HTML seguro (escape, h1–h3, p, ul/ol/li, a, strong/em, code/pre, hr) + CSS inline e-ink.
- [x] **3.2** `ui/article_view.lua`: overlay de lectura reutilizable desde MD/HTML generado; cabecera de metadatos y cierre a dashboard.
- [x] **3.3** Persistencia de artículos: guardar `.md` y `.html` con metadatos mínimos (frontmatter o bloque inicial) en rutas canónicas.
- [x] **3.4** `ui/actions.lua`: ruteo de acciones internas (`open_hn:<id>`, `open_digest:<date>`), con **fallback sin deep-links HTML** (lista/botones Lua) si el widget no expone taps navegables.
- [x] **3.5** Contrato de “abrir en lector” (opcional, desactivado por defecto): wrapper aislado a `ReaderUI:showReader` con nota de comportamiento de retorno.
- [x] **3.6** Plantilla base de errores/estados vacíos en lectura (“content unavailable”, “no markdown”, “corrupted file”).

> **Nota (2026-11-15):** base F3 implementada en repo (`lib/render/md_to_html.lua`, `lib/article_store.lua`, `ui/article_view.lua`, `ui/actions.lua`, wiring en `main.lua`/`ui/dashboard.lua`, config `open_in_reader_enabled` default off). Dashboard incluye acción interna de prueba para persistir/abrir artículo (MD→HTML) y retorno por rutas Lua estables. **Verificación en runtime KOReader/Kindle y cierre formal pendientes**; gates F1/F2 previos permanecen abiertos.

**Criterio de salida:** se puede renderizar y abrir un artículo de prueba persistido (MD→HTML) y volver al dashboard por ruta interna estable.  
**Verificación:** abrir/cerrar artículos de prueba, validar escape HTML, enlaces/encabezados básicos y fallback de navegación. *(pendiente ejecución/registro en dispositivo o entorno KOReader auxiliar)*

### Fase 4 — Clima (Open-Meteo + geocoding)
**Depende de:** Fases 2, 3 (para render/UI común) y 1 *(gates F1/F2 verificación y runtime F3 siguen pendientes en ledger; implementación F4 avanzada en repo sin cerrar gates previos)*
- [x] **4.1** Config UI/campos: lat/lon manual y nombre de lugar (mínimo F4 vía `ui/menus.lua`: búsqueda lugar, lat/lon, limpiar, toggle; config ya saneada en `lib/config.lua`).
- [x] **4.2** `lib/wmo.lua`: mapa WMO → texto EN.
- [x] **4.3** `lib/geocoding.lua`: búsqueda por nombre → lat/lon/place (Open-Meteo geocoding API, errores tipados vía `lib/http.lua`).
- [x] **4.4** `lib/weather.lua`: fetch forecast Open-Meteo, normalización `WeatherView`, guardado en `cache/weather.json` vía `lib/cache.lua`/`lib/weather_state.lua` + `lib/refresh.lua`.
- [x] **4.5** Integración en dashboard: actual + min/max; stale/cache timestamp; estado “configure location”.
- [x] **4.6** UX sin red: prompt “turn on WiFi and refresh” (`NetworkMgr:promptWifiOn`/fallback `runWhenOnline` cuando disponible) con callback y fallback a caché; refresh cache-first con presupuesto/reentrada.

> **Nota (2026-11-15):** base F4 implementada en repo (`lib/wmo.lua`, `lib/geocoding.lua`, `lib/weather.lua`, `lib/weather_state.lua`, `ui/menus.lua`, integración en `main.lua`/`ui/dashboard.lua`/`ui/actions.lua` refresh flow). **Verificación runtime KOReader/Kindle y cierre formal pendientes**; gates F1/F2/F3 previos permanecen abiertos.

**Criterio de salida:** clima funciona online, degrada correctamente offline y respeta TTL/cache. *(implementación en repo; pendiente validación en dispositivo/entorno KOReader)*  
**Verificación:** con/sin ubicación, con/sin red, caché vigente y expirada. *(pendiente ejecución/registro)*

### Fase 5 — Hacker News vía `hnmd`
**Depende de:** Fases 2, 3, 4 (integración visual en dashboard)
- [x] **5.1** Extender/confirmar config: `hnmd_enabled`, `hnmd_base_url` (default `https://hnmd.miguehm.com`), `hnmd_api_key`, `hnmd_max_items`, `hnmd_ttl_minutes`.
- [x] **5.2** UI ajustes HN: editar base URL, API key (enmascarada), max items, toggle; documentar edición manual en `settings/kindlehome.lua`.
- [x] **5.3** `lib/hnmd.lua`: GET `{base}/top` con `Authorization: Bearer` si aplica, parse/validación de respuesta (`generated_at,next_refresh_at,refresh_interval,count,items,last_refresh_error?`).
- [x] **5.4** Normalizar `NewsItem` → `HnItemView` y limitar por `hnmd_max_items` (orden `rank`).
- [x] **5.5** Cache `cache/hnmd.json`: snapshot + estado fetch, TTL configurable, stale fallback.
- [x] **5.6** Manejo HTTP/estado:
  - `200`: render + cache ok.
  - `503 warming_up`: mensaje y uso de caché si existe.
  - `401`: banner accionable a Settings, sin reintentos automáticos.
  - red/timeout/parse/otros: mensaje breve + caché si existe.
- [x] **5.7** Dashboard sección HN: lista con rank, título, score/comentarios/autor/dominio; marcar `status!=ok` o markdown vacío.
- [x] **5.8** Lectura de artículo HN: usar `article_view` + `md_to_html` con markdown del servidor; guardar `.md/.html` en `articles/hn/`.
- [x] **5.9** Caso `url == null` (Ask HN): no intentar fetch externo; mostrar solo contenido `hnmd`.
- [ ] **5.10** (Opcional MVP+) abrir URL externa en overlay con descarga limitada/timeout y error claro; si se pospone, documentar como no soportado.

> **Nota (2026-11-15):** base F5 implementada en repo (`lib/hnmd.lua`, `lib/hnmd_state.lua`, ajustes en `lib/config.lua`/`ui/menus.lua`/`ui/actions.lua`/`ui/dashboard.lua`/`main.lua`, docs README). Cache-first/stale vía `lib/cache.lua`/`lib/refresh.lua`, HTTP vía `lib/http.lua` (Bearer opcional, sin retry en 401), navegación por acciones Lua `open_hn:<id>` con fallback, persistencia `.md/.html` en `articles/hn/`. 5.10 (URL externa) queda pospuesto/documentado como no soportado. **Verificación runtime KOReader/Kindle y cierre formal pendientes**; gates F1–F4 previos permanecen abiertos.

**Criterio de salida:** HN lista y abre artículos `markdown` desde `hnmd` con cache y manejo correcto de `401/503`.  
**Verificación:** 200, 401, 503 warming_up, sin red con caché, item `status:error`/sin markdown, Ask HN (`url=null`). *(implementación en repo; pendiente validación en dispositivo/entorno KOReader)*

> **Actualizado (2026-11-16):** el contrato real de `hnmd` ya no entrega cuerpos en `/top`; 5.3/5.7/5.8 quedan sustituidos por el índice + descarga de `/v1/articles/{id}.md` de la **Fase 10**. Los chequeos de estado se leen ahora de `content_status`.

### Fase 6 — Digest y pulido de lectura
**Depende de:** Fases 4, 5 *(gates F1–F5 verificación runtime/ledger siguen pendientes; implementación F6 avanzada en repo sin cerrar gates previos)*
- [x] **6.1** `lib/digest.lua`: modelo de portada diaria (hora, clima, top HN) + render MD/HTML.
- [x] **6.2** Persistir `digest/YYYY-MM-DD.md/.html` y exponer “Open latest digest”.
- [x] **6.3** Unificar estilos HTML/CSS para MuPDF (simple, legible en e-ink) entre dashboard/artículos/digest.
- [x] **6.4** Mejoras de lectura: metadatos consistentes, estados vacíos, navegación de retorno predecible.
- [x] **6.5** (Opcional) acción “Abrir en lector” para archivos generados, detrás de flag/config.

> **Nota (2026-11-15):** base F6 implementada en repo (`lib/digest.lua`, ajustes en `lib/article_store.lua`/`ui/dashboard.lua`/`main.lua`, reutiliza `lib/render/md_to_html.lua`, `ui/article_view.lua`, `lib/paths.lua`). Generación/apertura desde estado cache-first (parciales soportados), persistencia atómica `digest/YYYY-MM-DD.md/.html`, acciones Lua `generate_digest`/`open_digest:<date|latest>` y retorno a dashboard. “Abrir en lector” disponible solo con flag/config existente y `html_path` (aislado, default off). **Verificación runtime KOReader/Kindle y cierre formal pendientes**; gates F1–F5 previos permanecen abiertos.

**Criterio de salida:** digest diario generado/abrible y lectura consistente entre fuentes disponibles. *(implementación en repo; pendiente validación en dispositivo/entorno KOReader)*  
**Verificación:** generar digest con datos parciales (p.ej. solo clima o solo HN), reabrir, revisar render. *(pendiente ejecución/registro)*

### Fase 7 — Ajustes completos, gestos y automatización
**Depende de:** Fases 4–6
- [x] **7.1** Menú de ajustes completo: clima, HN, rutas, TTLs, refresh policy, toggles de secciones.
- [x] **7.2** Dispatcher/documentación para gesto y Profiles (abrir al inicio / al despertar) con comportamiento seguro.
- [x] **7.3** Política de refresh al abrir: cache-first + refresco condicionado por TTL/red/presupuesto; indicador de progreso breve.
- [x] **7.4** Centralizar mensajes de error/estado en UI (sin stack traces, sin secretos).
- [x] **7.5** Endurecer límites: tamaño máximo de payload, número de items por ciclo, timeout global de actualización.

> **Nota (2026-11-15):** base F7 implementada en repo (`ui/menus.lua` completo, `ui/messages.lua`, ajustes en `main.lua`/`ui/dashboard.lua`/`lib/config.lua`/`lib/refresh.lua`/clientes HTTP y docs). Dispatcher seguro/idempotente y refresh cache-first condicionado con reentrada/progreso; límites y mensajes centralizados reforzados. **Verificación runtime KOReader/Kindle y cierre formal pendientes**; gates F1–F6 previos permanecen abiertos.

**Criterio de salida:** flujo diario completo (abrir panel → ver estado → refrescar → leer) usable y predecible. *(implementación en repo; pendiente validación en dispositivo/entorno KOReader)*  
**Verificación:** apertura automática/manual, offline/online, cancelación lógica por presupuesto (si aplica), reentrada de refresh. *(pendiente ejecución/registro)*

### Fase 8 — Endurecimiento, validación en dispositivo y empaquetado
**Depende de:** Fase 7
- [x] **8.1** Matriz de pruebas preparada (checklist desktop auxiliar + Kindle real) y smoke estático registrado en §10; **ejecución en Kindle real pendiente** (sin WiFi, WiFi inestable, 401/503/parse/too_large, lat/lon inválida, caché corrupta, settings incompletos, gates F1–F7).
- [x] **8.2** Revisión de budgets/TTLs/defaults realizada (sin cambios por falta de evidencia de dispositivo); **medición/performance en Kindle pendiente** y ajuste condicionado a evidencia.
- [x] **8.3** Revisión de seguridad/privacidad en repo completada: enmascarado de key en UI, sin logs de secretos/Authorization/payloads (auditoría), contratos de almacenamiento local/atomic writes documentados; **validación runtime en Kindle pendiente**.
- [x] **8.4** Documentación actualizada: `README.md`, `CHANGELOG.md`, troubleshooting, configuración `hnmd_api_key` (UI y archivo), rutas de datos y checklist de release.
- [x] **8.5** Empaquetado preparado en repo: versión `0.1.2` en `_meta.lua`, checklist de release documentado y zip instalable `kindlehome.koplugin-v0.1.2.zip` generado (sin directorios vacíos); **smoke de instalación desde zip en Kindle pendiente**. (v0.1.0 no cargaba y v0.1.1 crasheaba al primer gesto: ver §9/§10.)
- [ ] **8.6** (Opcional, diferido post-MVP) fallback HN alternativo, i18n completa, userpatch/screensaver experimental. **No implementar en MVP**; registrar seguimiento.

> **Nota (2026-11-15):** 8.1–8.5 completadas a nivel repo/preparación (artefactos, docs, checks estáticos). **Cierre formal de F8/MVP bloqueado hasta verificación en Kindle real** (matriz, performance, instalación desde zip) y registro en §10. 8.6 diferido por decisión de alcance.
> **Nota (2026-11-15, revisión 0.1.1):** la verificación en Kindle reveló que el `PASS` estático previo era inválido para el runtime real (Lua 5.3 en `lib/paths.lua` y registro de menús con `require` inexistente). Ambos defectos corregidos; el gate `scripts/check_lua51.sh` pasa a ser obligatorio antes de cualquier release.

**Criterio de salida:** MVP instalable, documentado y validado en dispositivo objetivo con fallos comunes controlados. *(repo preparado; validación Kindle pendiente)*  
**Verificación:** ejecución completa de matriz de pruebas y registro en ledger. *(pendiente en dispositivo)

### Fase 9 — Rediseño de UI para e-ink (PaperWhite 5), pantalla completa y salida clara
**Depende de:** Fase 8 (base estable 0.1.2)

- [x] **9.0** Tokens de UI y configuración: `lib/render/theme.lua` (`ui_font_scale` 0.85–1.6, tamaños nativos, CSS dashboard em-only) y nuevos defaults saneados en `lib/config.lua` (`ui_font_scale=1.0`, `ui_fullscreen=true`, `ui_show_test_article=false`).
- [x] **9.1** CSS relativo (em) en `lib/render/md_to_html.lua` y dashboard: el tamaño real lo gobierna `default_font_size = Screen:scaleBySize(26 * ui_scale)`; se eliminan `font-size:<n>px` (causa raíz de texto ilegible en 300 ppi).
- [x] **9.2** Dashboard HTML (`lib/render/dashboard_html.lua`): reloj/fecha como hero, una sola lista HN (sin duplicado “Actions”), títulos completos, metadatos, tiempos relativos, tarjetas con borde (sin grises que ghostean) y enlaces `kh:*` solo para leer.
- [x] **9.3** Shell nativo (`ui/shell.lua`) + barra de acciones (`ui/widget/action_bar.lua`): `covers_fullscreen`, refresco `full` al abrir/cerrar, TitleBar con icono de salida siempre visible, botones icono+etiqueta (target ≈ 58 dp), Back key y swipe-down en cabecera.
- [x] **9.4** Lector de artículo/digest sobre el mismo shell: cabecera con Back, pie con Reader (si está habilitado)/Close, sin navegación al final del HTML; retorno predecible al dashboard.
- [x] **9.5** Menú **Interface** (tamaño de texto S/M/L/XL, fullscreen, enlace de artículo de prueba) con refresco del dashboard abierto.
- [x] **9.6** Gates/smoke: `scripts/smoke/shell.lua` y `scripts/smoke/action_bar.lua` añadidos a `scripts/smoke_ui.sh`; dashboard/article smoke actualizados a shell + acciones nativas y validación de `covers_fullscreen`, alturas y callbacks.
- [x] **9.7** Docs/versionado: `README.md`, `CHANGELOG.md`, `_meta.lua` v0.2.0 y zip `kindlehome.koplugin-v0.2.0.zip`.
- [ ] **9.8** Verificación en Kindle PW5: capturas baseline (retrato/apaisado), legibilidad a distancia, targets, salida por icono/Back/swipe, fullscreen sin ghosting, rotación y refresco; registrar PASS/FAIL en §10.

> **Nota (2026-11-15):** F9 implementada en repo con arquitectura híbrida (nativo + HTML). Decisiones: pantalla completa con `covers_fullscreen` y refresco completo al abrir/cerrar; salida redundante (icono, botón Exit, Back, swipe-down en cabecera); UI en inglés; iconos MDLight (sin unicode en HTML, por sustitución de fuentes poco fiable en MuPDF). El CSS usa solo unidades relativas para tipografía. **Validación visual/ergonómica en dispositivo pendiente (9.8).**

**Criterio de salida:** dashboard legible y operable en PW5 en retrato/apaisado, con salida siempre visible y sin artefactos e-ink. *(implementación en repo; pendiente verificación 9.8)*  
**Verificación:** matriz F9 en Kindle + `check_lua51.sh`, `check_invariants.sh`, `smoke_ui.sh`. *(estático PASS; dispositivo pendiente)*

### Fase 10 — Artículos Markdown descargados desde `hnmd` (lectura nativa, sin overlay)
**Depende de:** Fases 5, 9 (contrato `hnmd` validado con datos reales el 2026-11-16)

- [x] **10.1** `lib/config.lua`: `hnmd_base_url` default `https://hnmd.miguehm.com/v1` (host desnudo → `/v1`), `index_max_bytes=131072`, `article_max_bytes=524288` con clamps; retirado `open_in_reader_enabled`.
- [x] **10.2** `lib/http.lua`: `Http.get_to_file` (sink a archivo, `too_large` por contador, `incomplete` por `Content-Length`, `.tmp` borrado en fallo, retry solo transitorio) y `http_404`.
- [x] **10.3** `lib/hnmd.lua`: `fetch_index` (valida `schema_version==1`, normaliza `content_status`/`content_url`/`content_length`, ordena por rank) y `download_article` (resuelve `content_url` contra el origen, rechaza cross-origin y base no-https, verifica longitud declarada).
- [x] **10.4** `lib/paths.lua`: `article_md_path` (`<id>-<slug>.md`) y `article_html_path` (`<md>.html`).
- [x] **10.5** `lib/article_store.lua`: `is_local`, `ensure_local` (descarga solo si falta/vacío; promoción atómica `os.rename`) y `render_derived` (regenera si `mtime(html) < mtime(md)`; strip de frontmatter propio).
- [x] **10.6** `ui/dashboard.lua`: tap → `ensure_local` con aviso breve, apertura vía `article_view`/`ReaderUI`; estados `no_content`/`warming_up`/`http_404` con mensaje corto; fallback a overlay con Markdown crudo si el render falla.
- [x] **10.7** `ui/article_view.lua`/`ui/messages.lua`: retirado flag/acción `kh:reader` y añadidos `http_404`, `incomplete`, `no_content`, `warming_up`, `offline_no_local`, `downloading`.
- [x] **10.8** Render: `h4`–`h6`, `blockquote`, imágenes → alt (sin cargas remotas), `<!DOCTYPE html>`/`<title>`; `Cache.SCHEMA_VERSION=2`.
- [x] **10.9** Gates/smokes: `article_download.lua`, `md_render.lua`, `hnmd_url.lua`, `http_stream.lua`; invariantes nuevos (descarga vía `get_to_file`, `ui/` sin HTTP ni borrados, `os.remove/rename` solo sobre `.tmp`); `PLAN`/`AGENTS`/`README`/`CHANGELOG` y `_meta.lua` 0.3.0.
- [ ] **10.10** Verificación en Kindle PW5: descarga real de `50517488` (7938 B) y `50516473` (72644 B), apertura en `ReaderUI` con progreso/anotaciones, segundo tap sin re-descarga, 404/offline con copia local intacta, `.tmp` sin residuos; registrar en §10.

> **Nota (2026-11-16):** contrato validado contra el backend real (`/v1/top` índice, `HEAD`/`GET /v1/articles/{id}.md`, `schema_version:1`, `content_status`, `content_length`, 401 con `WWW-Authenticate`). `content_url` es **origin-absolute** (`/v1/...`): se resuelve contra `https://host` para no producir `/v1/v1/...`. KOReader v2026.07 registra `md` como `text/plain` (crengine lo muestra crudo), por eso el `.md.html` derivado es el que abre el lector nativo; el `.md` queda como copia canónica. Deuda conocida: al salir del lector se vuelve al explorador de archivos, no al dashboard.

**Criterio de salida:** cada artículo HN se lee en `ReaderUI` desde un `.md` local duradero, sin overlay como flujo principal y sin re-descargas innecesarias. *(implementación en repo; pendiente 10.10)*  
**Verificación:** datos reales, `check_lua51.sh`, `check_invariants.sh`, `smoke_ui.sh`, Kindle PW5.

## 7) Matriz de verificación mínima (por fase)

> **Referencia:** la validación objetivo es **Kindle real** (e-ink/KOReader). Pruebas en desktop/PC son auxiliares y no sustituyen la verificación en Kindle.

- **F0–F1 (UI/local):** en Kindle: carga plugin, navegación básica, refresh, sin errores en log (desktop auxiliar opcional).
- **F2 (transversal):** timeout, HTTP 401/503/500 simulado o forzado, JSON inválido, caché corrupta, escritura atómica.
- **F3 (lectura):** render MD básico, escape HTML, persistencia `.md/.html`, apertura/cierre overlay, fallback navegación.
- **F4 (clima):** ubicación válida/inválida, geocoding OK/fail, online/offline, TTL expirado.
- **F5 (hnmd):** 200, 401, 503 `warming_up`, red caída, item sin markdown/error, Ask HN `url=null`.
- **F6–F7 (integración):** digest parcial/completo, refresh al abrir, gestos/profiles, reentrada.
- **F8 (dispositivo):** smoke + regresión en **Kindle real** y tiempos aceptables (obligatorio para cierre MVP).
- **F9 (UI/e-ink):** legibilidad y targets en PW5 (retrato/apaisado), fullscreen/refresco sin ghosting, salida por icono/Back/swipe, tamaño S–XL y rotación sin pérdida de estado.
- **F10 (artículos `.md`):** descarga real de 2 ids, `ReaderUI` con `.md.html`, segundo tap sin red, `404`/offline conserva copia local, `.tmp` limpio, límites `article_max_bytes`.

## 8) Riesgos, mitigaciones y decisiones abiertas

### Riesgos (con mitigación)
- **UI bloqueada durante red/parse:** fetch secuencial, timeouts cortos, límites de bytes, presupuesto global, refresh manual explícito.
- **Navegación HTML limitada en widgets KOReader:** acciones internas Lua como fuente de verdad; deep-links HTML solo como mejora si se confirma soporte.
- **Render MuPDF/CSS limitado:** HTML simple, sin dependencias visuales complejas, estilos inline mínimos y probados.
- **Dependencia externa `hnmd`:** cache-first, stale fallback, mensajes específicos por estado, posibilidad futura de fallback alternativo.
- **Persistencia de API key en texto plano:** enmascarar en UI, no loguear, documentar riesgo y rotación.
- **Datos/caché corruptos o versión incompatible:** envelope versionado + recuperación automática (reset controlado).

### Decisiones abiertas (registrar al resolver)
- [ ] Ruta por defecto final: `documents/KindleHome` vs `<DataDir>/news/kindlehome` (priorizar visibilidad o limpieza del explorador).
- [ ] Mecanismo de navegación a artículos: solo acciones Lua vs híbrido (Lua + enlaces HTML) tras prueba en `ScrollHtmlWidget`.
- [ ] Política exacta de refresh automático al abrir (solo stale, solo WiFi, máximo por intervalo).
- [ ] ¿Habilitar “Abrir en lector” en MVP o dejarlo para post-MVP?

## 9) Registro de desviaciones / deuda (plantilla)

> Registrar toda divergencia del plan con fecha, motivo, impacto y estado. No borrar entradas; cerrar como resuelta o diferida.

| Fecha | Fase/Tarea | Desviación | Motivo | Impacto | Estado | Resolución / seguimiento |
|---|---|---|---|---|---|---|
| 2026-11-15 | Global / R1–R5 | Retiro de soporte RSS/Atom; renumeración de fases (antigua F6 RSS eliminada, F7→F6, F8→F7, F9→F8); actualización de contratos/arquitectura/criterios y limpieza de defaults/rutas RSS en repo | Solicitud explícita: solo HN vía `https://hnmd.miguehm.com/top` | Medio (simplifica alcance; elimina código/config RSS planificado) | ✔ resuelta (plan + repo base) | R1–R5 aplicados; registrar verificación adicional en §10 según corresponda |
| 2026-11-15 | F3 (pre-gate F1/F2) | Implementación de base Fase 3 en repo antes de cerrar verificación F1 en Kindle y verificación/cierre formal F2 | Avance solicitado de “siguiente fase pendiente” para disponer de renderer/navegación/persistencia reutilizables | Medio (riesgo de integración no validada en dispositivo/runtime) | ⏸ diferida (verificación) | Completar gates F1/F2 y ejecutar verificación F3 en KOReader (Kindle objetivo + auxiliar opcional), registrar en §10; no considerar fase cerrada hasta evidencia |
| 2026-11-15 | F4 (pre-gate F1/F2/F3) | Implementación de base Fase 4 (clima Open-Meteo/geocoding/cache/UI) en repo antes de cerrar verificación runtime F1–F3 y ledgers | Continuación solicitada de fase pendiente para habilitar integración clima en dashboard | Medio (riesgo de regresión/integración no validada en KOReader/Kindle; dependencias de APIs externas no probadas en dispositivo) | ⏸ diferida (verificación) | Ejecutar y registrar verificación F4 (§6/§7: ubicación válida/inválida, online/offline, TTL, geocoding, stale/prompt WiFi) y cerrar gates F1–F3 en §10; revisar comportamiento de `NetworkMgr:promptWifiOn` en Kindle real |
| 2026-11-15 | F5 (pre-gate F1–F4) | Implementación de base Fase 5 (hnmd client/cache/state, settings/UI, dashboard HN, lectura/persistencia markdown) en repo antes de cerrar verificación runtime F1–F4 y ledgers | Continuación solicitada de fase pendiente para integrar HN vía hnmd | Medio (riesgo de integración no validada en KOReader/Kindle; dependencia externa hnmd/auth/estados no probados en dispositivo) | ⏸ diferida (verificación) | Ejecutar y registrar verificación F5 (§6/§7: 200, 401 sin retry, 503 warming_up, offline con caché, item error/sin markdown, Ask HN url=null, TTL/presupuesto/reentrada) y cerrar gates F1–F4 en §10; mantener 5.10 pospuesto salvo decisión explícita |
| 2026-11-15 | F6 (pre-gate F1–F5) | Implementación de base Fase 6 (digest diario, persistencia/apertura/pulido de lectura) en repo antes de cerrar verificación runtime F1–F5 y ledgers | Continuación solicitada de fase pendiente para integrar digest y pulir lectura | Medio (riesgo de integración/render/navegación no validada en KOReader/Kindle; datos parciales no probados en dispositivo) | ⏸ diferida (verificación) | Ejecutar y registrar verificación F6 (§6/§7: digest clima+HN, solo clima, solo HN, sin datos; persistencia/reapertura/latest; navegación/retorno; regresión HN/Ask HN; render e-ink) y cerrar gates F1–F5 en §10; validar 6.5 flag/ReaderUI en Kindle si se habilita |
| 2026-11-15 | F7 (pre-gate F1–F6) | Implementación de base Fase 7 (ajustes completos, Dispatcher/gesto-profile docs, política refresh/progreso, mensajes UI centralizados, endurecimiento de límites) en repo antes de cerrar verificación runtime F1–F6 y ledgers | Continuación solicitada para completar fase pendiente de integración/automatización | Medio (riesgo de regresión UX/refresh/config no validada en KOReader/Kindle; comportamiento de Dispatcher/prompts WiFi dependiente de runtime) | ⏸ diferida (verificación) | Ejecutar y registrar verificación F7 (§6/§7: settings persist/sanitize, apertura manual/gesto/profile, cache-first TTL/red/presupuesto, reentrada, offline/401/503/too_large/budget, mensajes sin secretos/stack traces) y cerrar gates F1–F6 en §10 |
| 2026-11-15 | F8/8.6 | 8.6 diferido (fallback HN alternativo, i18n completa, screensaver/userpatch) para mantener MVP enfocado | Decisión de alcance (usuario): Kindle disponible pero 8.6 no requerida para MVP | Bajo (funcionalidad post-MVP no entregada) | ⏸ diferida (post-MVP) | Re-evaluar tras cierre MVP F1–F8 en Kindle; registrar como backlog/issue futuro si aplica |
| 2026-11-15 | F8/8.1-8.3 (device) | Verificación runtime en Kindle (matriz F1–F8, performance, seguridad/privacidad en dispositivo) no ejecutada en este entorno | Sin acceso a runtime KOReader/Kindle durante esta sesión; usuario indicó Kindle disponible para fase | Medio/alto para cierre formal (evidencia de dispositivo ausente) | ⏸ diferida (verificación en Kindle) | Ejecutar matriz §7/§6 en Kindle real (FW/KOReader versionados), registrar PASS/FAIL/evidencia en §10, aplicar fixes si hay fallos y repetir |
| 2026-11-15 | F8/8.1 (carga en Kindle) | **Defecto bloqueante detectado en dispositivo:** `lib/paths.lua:55` usaba XOR bit a bit (`h ~ s:byte(i)`, sintaxis Lua 5.3+) → KOReader (Lua 5.1/LuaJIT) rechaza `main.lua` al cargar (`WARN Error when loading … paths.lua:55: unexpected symbol near '~'`); el plugin no aparecía en menús ni en Plugin management. El `luac -p` del sistema (5.5) validaba en falso | Verificación real en Kindle PaperWhite 5 (KOReader v2026.03) destapó el fallo; el gate estático previo usaba un `luac` incompatible con el runtime objetivo | Alto (plugin inoperante; invalida el "PASS estático" previo de F8 como garantía para dispositivo) | ✔ resuelta (repo 0.1.1) | `short_hash` reemplazado por hash aritmético sin operadores bit a bit (formato `%04x%04x` por mitades de 16 bits, seguro en Lua 5.1); nuevo gate obligatorio `scripts/check_lua51.sh` (`luac5.1`/`lua5.1`/`luajit`) documentado en `AGENTS.md`; evidencia en §10 |
| 2026-11-15 | F7/7.x (menús) | **Defecto funcional:** `ui/menus.lua` hacía `require("ui/elements/menu_items")` (módulo inexistente en KOReader) y registraba el menú fuera del mecanismo oficial; `main.lua:39` lo silenciaba con `pcall`, así que el submenú de ajustes nunca se registraba | Detección durante el diagnóstico de carga; el patrón correcto es `addToMainMenu(menu_items)` invocado por `ReaderMenu`/`FileManagerMenu` | Medio (dashboard alcanzable por Dispatcher, pero ajustes inaccesibles) | ✔ resuelta (repo 0.1.1) | `Menus:add_settings(menu_items, main_instance)` registra una única entrada `kindlehome` (`sorting_hint="tools"`) con "Open dashboard" + secciones; eliminado el `pcall`, el código muerto de `main.lua` y `name` deprecado de `_meta.lua`; zip regenerado sin directorios vacíos `lib/rss/` |
| 2026-11-15 | F8/8.1 (crash en dispositivo) | **Defecto bloqueante:** `ScrollHtmlWidget` creado sin `dialog` en `ui/dashboard.lua` y `ui/article_view.lua` → al primer swipe/tap KOReader aborta (`attempt to index field 'dialog' (a nil value)` en `scrollhtmlwidget.lua:182`). Además `actions`/`title` no son campos del widget (las acciones nunca se renderizaban) y el cuerpo HTML se pasaba como documento completo (anidado). | Verificación real en Kindle PaperWhite 5 + KOReader v2026.07: 3 tracebacks tras `[KindleHome] event=shown` | Alto (app inutilizable; pérdida de sesión de lectura) | ✔ resuelta (repo 0.1.2) | `widget.dialog = widget` antes de `UIManager:show`; acciones como enlaces `kh:*` vía `html_link_tapped_callback`; `MdToHtml.document_body` (fragmento + `css`); `Actions:dispatch` usa forma `prefijo:arg`; nuevo gate `scripts/check_invariants.sh` |
| 2026-11-15 | F7/F8 (red y rutas) | `refresh_on_open` default `true` ejecutaba geocoding+clima+HN síncronos antes del primer pintado (hasta ~30 s de UI bloqueada); `http_max_bytes` 512 KiB con 15 MB libres; contenido escrito en `/mnt/us/koreader/KindleHome` (`getFullDataDir()` = dir de instalación en Kindle) | Riesgo de watchdog/OOM en dispositivo con poca RAM; contenido invisible en la biblioteca del Kindle | Medio | ✔ resuelta (repo 0.1.2) | `refresh_on_open=false` en MVP (refresco diferido con `UIManager:scheduleIn` si se activa); `http_timeout_s` 10→6 s; `http_max_bytes` 512→256 KiB; `documents_root()` resuelve `<home_dir>/documents/<subdir>` (`/mnt/us/documents/KindleHome`) |
| 2026-11-16 | F10 (pre-gate F1–F9) | Migración de “markdown embebido en `/top`” a índice + descarga de `/v1/articles/{id}.md`, `.md` canónico + `.md.html` derivado, retirada de `open_in_reader_enabled` y del overlay como flujo principal | Contrato real de `hnmd` validado con datos de producción: `/top` ya no entrega cuerpos; el lector nativo solo renderiza HTML y `md` se abre como texto plano en credocument | Medio (cambio incompatible de `/top` y del flujo de lectura; caché v1 invalidada) | ✔ resuelta (repo 0.3.0) | `hnmd.fetch_index`/`download_article`, `Http.get_to_file` (streaming), `article_store.ensure_local`/`render_derived`, `SCHEMA_VERSION=2`, smokes e invariantes nuevos. Breaking change documentado en `CHANGELOG.md`; verificación 10.10 en Kindle pendiente |
| 2026-11-16 | F9 (scroll en dispositivo) | **Defecto funcional:** `ScrollHtmlWidget` recibía `dialog` apuntando al cuerpo anidado (`dashboard.lua:530`, `article_view.lua:160`); `UIManager:setDirty` solo marca widgets en `_window_stack`, así que el swipe/tap encolaba el refresh (flash e-ink) pero no repintaba la página siguiente. La paginación era correcta (4 páginas a 1400 px), por lo que no era un fallo de MuPDF | Diagnóstico por SSH en Kindle PW5 / KOReader v2026.07: `modes` 1236×1648, `virtual_size` 1248×3296 (doble búfer); `logger` sin tracebacks; taps despachaban `open_hn:*`; artículos en `ReaderUI`; RAM 102 MB libres / 154 MB disponibles | Alto (dashboard inutilizable: no se puede leer la lista HN) | ✔ resuelta (repo 0.3.1, validado en dispositivo) | `Shell:init` asigna `body.dialog`, `body.show_parent` y `body.htmlbox_widget.dialog` al `Shell`; eliminadas las auto-asignaciones en dashboard/article; invariante y smokes reescritos (destino de repintado = widget superior). Re-test en Kindle PW5 PASS (navegación restablecida). Siguiente: refactor de cuerpo nativo |
| YYYY-MM-DD | F0/0.x | (ej.) Se cambió ruta de cache | (motivo) | (bajo/medio/alto) | ⏸ diferida / ✔ resuelta | (acción tomada o pendiente) |

## 10) Ledger de verificación (plantilla)

> Registrar cada ejecución relevante de verificación (por fase, regresión o pre-release).

| Fecha | Fase | Entorno | Qué se verificó | Resultado | Evidencia / notas | Flakes / pendientes |
|---|---|---|---|---|---|---|
| 2026-11-15 | Cambio de alcance (sin RSS) | Linux dev (repo) | Búsqueda `rss/RSS/FeedItemView/open_rss/articles/rss` en repo; revisión de `config.lua`, `paths.lua`, `README.md`, `PLAN.md` tras R1–R5 | PASS | `grep` sin coincidencias en `kindlehome.koplugin/README.md/AGENTS.md`; claves/rutas RSS removidas. Sin runtime KOReader en este entorno. | Gates previos siguen pendientes: verificación F1 en Kindle real y cierre/ledger F2 (§6 F1/F2) |
| 2026-11-15 | F3 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos nuevos/modificados F3 (`lib/render/md_to_html.lua`, `lib/article_store.lua`, `ui/actions.lua`, `ui/article_view.lua`, `ui/dashboard.lua`, `main.lua`, `lib/config.lua`); revisión de wiring y contratos (escape/sanitización básica links, atomic write, rutas internas, open_in_reader flag off) | PASS (sintaxis/wiring estático) | Sin runtime KOReader en entorno; no valida `UIManager/ScrollHtmlWidget/ReaderUI` en dispositivo. | Pendiente: verificación funcional F3 + gates F1/F2 en KOReader (Kindle objetivo) y registro de resultados |
| 2026-11-15 | F4 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos F4/nuevos o modificados (`lib/wmo.lua`, `lib/geocoding.lua`, `lib/weather.lua`, `lib/weather_state.lua`, `ui/menus.lua`, `ui/dashboard.lua`, `main.lua`) y revisión estática de contratos (cache-first/stale vía `refresh/cache`, uso de `lib/http`, presupuesto/reentrada, mensajes UI breves, sin secretos en logs) | PASS (sintaxis/wiring estático) | Sin runtime KOReader ni red real/Kindle en entorno; no valida Open-Meteo/geocoding en dispositivo, prompts WiFi, ni render/timings en e-ink. | Pendiente: verificación funcional F4 (ubicación válida/inválida, online/offline, TTL, caché vigente/expirada, geocoding OK/fail) y gates F1–F3 en KOReader (Kindle objetivo) |
| 2026-11-15 | F5 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos F5 nuevos/modificados (`lib/hnmd.lua`, `lib/hnmd_state.lua`, `ui/menus.lua`, `ui/dashboard.lua`, `main.lua`, `ui/actions.lua`) y revisión estática de contratos (HTTP vía `lib/http.lua` con Bearer opcional/retry transitorio sin 401, cache-first/stale/envelope, rutas/actions Lua, persistencia atómica artículos HN, API key enmascarada en UI y no registrada en logs, manejo Ask HN/url null sin fetch externo, 5.10 pospuesto) | PASS (sintaxis/wiring estático) | Sin runtime KOReader/Kindle ni endpoint hnmd real verificado en dispositivo; no valida 200/401/503 warming_up en vivo, UI e-ink, prompts/refresh behavior, ni lectura/persistencia en filesystem objetivo. | Pendiente: verificación funcional F5 y gates F1–F4 en KOReader (Kindle objetivo), registrar evidencia y actualizar estado de cierre |
| 2026-11-15 | F6 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos F6 nuevos/modificados (`lib/digest.lua`, `lib/article_store.lua`, `ui/dashboard.lua`, `main.lua`) y revisión estática de contratos (digest desde estado cache-first con parciales, persistencia atómica `digest/YYYY-MM-DD.md/.html`, acciones Lua `generate_digest`/`open_digest:<date|latest>`, retorno a dashboard, reutiliza `MdToHtml`/`article_view`, sin fetch adicional bloqueante dedicado, 6.5 detrás de flag existente) | PASS (sintaxis/wiring estático) | Sin runtime KOReader/Kindle en entorno; no valida render e-ink/MuPDF, navegación/retorno real, parciales con datos reales, ni reapertura tras regeneración en dispositivo. | Pendiente: verificación funcional F6 y gates F1–F5 en KOReader (Kindle objetivo), registrar evidencia y actualizar estado de cierre |
| 2026-11-15 | F7 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos F7 nuevos/modificados (`ui/messages.lua`, `ui/menus.lua`, `ui/dashboard.lua`, `main.lua`, `lib/config.lua`, `lib/weather_state.lua`, `lib/hnmd_state.lua`, `ui/article_view.lua`, `lib/hnmd.lua`, `lib/weather.lua`, `lib/geocoding.lua`) y revisión estática de contratos (menú completo + toggles/TTLs/presupuesto, Dispatcher `kindlehome_show_dashboard` idempotente documentado, refresh cache-first condicionado TTL/red/presupuesto con reentrada/indicador breve, mensajes centralizados, límites http/bytes/budget/items aplicados, sin secretos en logs/UI) | PASS (sintaxis/wiring estático) | Sin runtime KOReader/Kindle en entorno; no valida gestos/Profiles/prompts WiFi reales, comportamiento de refresh en dispositivo, ni UX e-ink. | Pendiente: verificación funcional F7 y gates F1–F6 en KOReader (Kindle objetivo), registrar evidencia y actualizar estado de cierre |
| 2026-11-15 | F8 (repo prep 8.1–8.5) | Linux dev (repo) | `luac -p` PASS en todos los `kindlehome.koplugin/**/*.lua` (22 archivos); auditoría estática: sin logging de `hnmd_api_key`/Authorization/payloads sensibles (logger estructurado por módulo/evento), API key enmascarada en UI/menús; revisión de contratos (HTTP vía `lib/http.lua`, retries sin 401, cache-first/stale, atomic writes/quarantine, rutas canónicas, mensajes centralizados). Bump `_meta.lua` a `0.1.0`, creación de `README.md` actualizado y `CHANGELOG.md`, generación de `kindlehome.koplugin-v0.1.0.zip` (contenido verificado: solo `kindlehome.koplugin/`). | PASS (preparación repo/estática) | No sustituye verificación Kindle. Defaults/budgets/TTLs sin cambios por falta de medición en dispositivo. 8.6 diferido. | Pendiente: ejecutar matriz F1–F8 en Kindle real (incl. 401/503/timeout/parse/too_large/offline inestable, geocoding/TTL, caché corrupta, digest/lectura/persistencia, Dispatcher/gesto/Profile, refresh_on_open/reentrada, performance, instalación desde zip), registrar evidencia FW/KOReader/logs y cerrar gates |
| 2026-11-15 | F8/8.1 (carga en Kindle) | Kindle PaperWhite 5 — KOReader v2026.03 (LuaJIT) | Carga inicial del plugin instalado en `/mnt/us/koreader/plugins/kindlehome.koplugin/` (copia verificada byte a byte; estructura plana `main.lua`/`_meta.lua`/`lib`/`ui`) y lectura de `crash.log` | **FAIL** (v0.1.0) | `11/15/26-16:36:23 WARN Error when loading plugins/kindlehome.koplugin/main.lua error loading module 'lib/paths' … paths.lua:55: unexpected symbol near '~'`; `/mnt/us/koreader/cache/kindlehome` inexistente; sin entrada en Tools ni en Plugin management → User plugins (evidencia de que `init()` no corrió) | Corregido en repo (0.1.1); pendiente reinstalar y repetir carga |
| 2026-11-15 | F8/8.5 (gate Lua 5.1) | Linux dev (repo) | `luac5.1 -p` sobre los 22 `.lua` del plugin (reproduce el fallo del dispositivo en `lib/paths.lua:55`), ejecución de `scripts/check_lua51.sh` tras el fix y prueba negativa con archivo sintético (`a ~ b`) para validar exit≠0 | PASS (tras fix) | Antes: `luac5.1: lib/paths.lua:55: unexpected symbol near '~'`. Después: `OK: all kindlehome.koplugin Lua files parse as Lua 5.1 (luac5.1)`. Prueba negativa: `FAIL: …/bitwise_bad.lua` + `'<eof>' expected near '~'`, exit=1. Nota: el `luajit` 2.1 de este host acepta `~` (build no representativo) y el `luac` del sistema es 5.5; ninguno sirve como gate | Confirmación en Kindle de carga sin `WARN` (pendiente). Hash verificado determinista entre Lua 5.1 y 5.5 con multiplicador `65599` (con `16777619` el producto supera 2^53 y divergía en dobles) |
| 2026-11-15 | F8/8.1 (interacción dashboard) | Kindle PaperWhite 5 — KOReader v2026.07, LuaJIT 2.1.1783773675 | Abrir dashboard (menú Tools y estado cacheado), swipe/tap, abrir artículo; revisión de `crash.log` | **FAIL** (v0.1.1) | `crash.log` líneas 6001/6153/6284: `./luajit: frontend/ui/widget/scrollhtmlwidget.lua:182: attempt to index field 'dialog' (a nil value)` justo tras `[KindleHome] module=dashboard event=shown`; memoria 474 MB total / 15 MB libres / swap 127/127; HN 200 con 10 items tras guardar API key; `weather=configure_location` | Corregido en repo 0.1.2; **pendiente re-test en dispositivo** (swipe/tap 4 direcciones, barra, artículo, digest) |
| 2026-11-15 | F9 (UI/e-ink) | Linux dev (repo) | Rediseño completo: tokens `theme.lua`, CSS em-only, dashboard HTML sin duplicados, shell fullscreen con TitleBar/ActionBar, lector en shell, menú Interface; gates `check_lua51.sh`, `check_invariants.sh`, `smoke_ui.sh` (dashboard, article_view, shell, action_bar) | PASS (repo/estático) | `smoke_ui.sh`: dashboard body 929 B/css 1083 B, article 110 B, shell 1200×1420, action bar 3 botones; `covers_fullscreen`, alturas y callbacks verificados en stubs | Pendiente 9.8 en Kindle PW5: capturas retrato/apaisado, legibilidad, targets, salida, ghosting, rotación; ajustar `ui_font_scale`/alturas con evidencia |
| 2026-11-15 | F9.1 (causa raíz) | Kindle PW5 — KOReader v2026.07 | Diagnóstico de texto ilegible: `font-size` absolutos en px (`dashboard.lua:237-244`, `md_to_html.lua:5-16`, `article_view.lua:127-128`) anulaban el `default_font_size` escalado por DPI (`Screen:scaleBySize(20)`); PW5 1236×1648 a 300 ppp ⇒ ~2.06 px/dp | ✔ resuelta (repo 0.2.0) | CSS migrado a unidades relativas (em) y base 26 dp escalada; tamaños nativos vía `Theme.native_size`; `ui_font_scale` aplica a HTML y barra | Confirmar en dispositivo que el cuerpo queda ≥ ~44 px y que S/M/L/XL cambia el render |
| 2026-11-15 | Gates estáticos (repo) | Linux dev | `luac5.1 -p` (22 archivos) + `scripts/check_invariants.sh` (ScrollHtmlWidget con `dialog`; sin `ui/elements/menu_items`) y prueba negativa del invariante | PASS | `OK: all kindlehome.koplugin Lua files parse as Lua 5.1 (luac5.1)`; 
| 2026-11-15 | Smoke offline UI (repo) | Linux dev (`lua5.1` + módulos KOReader simulados) | `scripts/smoke_ui.sh`: construye dashboard y artículo, valida `css`/fragmento (sin `<html>`), `dialog`, callback de enlaces (`kh:refresh`, `kh:hn:<id>`, `kh:digest`, `kh:close`, `kh:back`, `kh:dashboard`) y ausencia de `kh:reader` cuando está desactivado | PASS | `OK dashboard smoke: body=1268B css=461B dispatching=4`; `OK article_view smoke: body=321B`; `OK: UI smoke tests (lua5.1)` | Render real en e-ink aún depende del re-test en dispositivo |
| 2026-11-16 | Contrato `hnmd` (backend real) | Linux dev + endpoint de producción | `GET /v1/top` (índice, `schema_version=1`), `HEAD`/`GET /v1/articles/50517488.md` y `50516473.md`, 401 sin token (`WWW-Authenticate: Bearer`) | PASS | Índice sin cuerpos con `content_status`/`content_url`/`content_length`; artículos 7938 B y 72644 B (`text/markdown`, `Content-Disposition`); `content_url` resultó origin-absolute (`/v1/...`) → resolución contra origen | `404` real y `503+Retry-After` no ejercitados (manejo genérico); sin clave API en esta máquina |
| 2026-11-16 | F10 (impl. base) | Linux dev (repo) | `check_lua51.sh`, `check_invariants.sh` (nuevos guards: `hnmd` usa `get_to_file`, `ui/` sin HTTP ni `os.remove/rename`, `article_store` solo toca `.tmp`), `smoke_ui.sh` (8 smokes: dashboard, article_view, shell, action_bar, md_render, article_download, hnmd_url, http_stream) | PASS (estático/offline) | `smoke_ui.sh`: article download (sin re-descarga, `404` conserva copia, `.tmp` limpio), md render (`h4`–`h6`/blockquote/imágenes sin `img`/escape), hnmd URL (`/v1`, relativo, cross-origin rechazado). Sin runtime KOReader/PW5 | Pendiente 10.10 en Kindle: datos reales, `ReaderUI`, progreso/anotaciones, límites y residuos `.tmp` |
| 2026-11-16 | Hotfix scroll 0.3.1 (diagnóstico) | Kindle PW5 — KOReader v2026.07 (SSH, solo lectura) | `git-rev` v2026.07; `modes` U:1236x1648p-0; `virtual_size` 1248x3296 (doble búfer, no usar); md5 de `scrollhtmlwidget.lua`/`htmlboxwidget.lua`/`mupdf.lua` idénticos a .07.1; layout del dashboard 1236x1400 → `pages=4`/`usedH≈4139` en device y en repo; `crash.log` sin `[KindleHome]` errors; `settings/kindlehome.lua` con `ui_fullscreen=true`; `gestures.lua` sin swipes globales de pantalla completa | FAIL funcional pre-fix / diagnóstico PASS | Pruebas manuales: sin scrollbar aparente, 1 titular visible y cortado, tap/swipe/flick no avanzan, sí parpadea; barra de acciones visible; artículos abiertos en `ReaderUI` (`opened_in_reader`) | Re-test 0.3.1 en Kindle PW5 PASS (2026-11-16): flick/tap avanzan de página |
| 2026-11-16 | Hotfix scroll 0.3.1 (repo) | Linux dev | `check_lua51.sh`, `check_invariants.sh` (nuevo guard: `Shell` debe cablear `body.dialog`/`body.show_parent`; prohibida auto-asignación de `dialog`), `smoke_ui.sh` (dashboard/article/shell verifican `dialog == shell` y `show_parent == shell`) | PASS | `OK: all kindlehome.koplugin Lua files parse as Lua 5.1 (luac5.1)`; `OK: plugin invariants (top-level repaint target, menu registration, streamed downloads)`; 8 smokes PASS | Evidencia en Kindle 2026-11-16: navegación dashboard PASS (flick/tap); rotación y fallback pendientes |
| YYYY-MM-DD | F0 | KOReader desktop Linux / Kindle FW ... | Carga plugin, abrir/cerrar dashboard | PASS/FAIL | log, screenshot, pasos | (si aplica) |

## 11) Criterios de aceptación del MVP (definición de terminado)

- El plugin está enfocado y validado para **Kindle (KOReader, e-ink)**; no se considera objetivo de soporte PC/desktop.
- Dashboard abre desde menú/gesto en Kindle y muestra hora/fecha + estado básico + secciones disponibles.
- Clima y HN (`hnmd`) funcionan con **cache-first**, estados de error manejados y sin crashes offline.
- HN soporta `hnmd_api_key` por UI y por `settings/kindlehome.lua`, con manejo correcto de `200/401/503 warming_up` contra `https://hnmd.miguehm.com/top` (o `hnmd_base_url` configurada).
- Artículos HN se descargan como `.md` canónico (streaming, sin RAM) con `.md.html` derivado y se leen en el lector nativo (`ReaderUI`); el digest persiste en `.md/.html` y se reabre.
- Configuración y rutas están documentadas; no se registran secretos en logs; caché corrupta se recupera automáticamente.
- Existe verificación registrada por fases críticas y **smoke/regresión en Kindle real** (obligatorio).