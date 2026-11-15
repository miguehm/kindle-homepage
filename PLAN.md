# Plan de implementación — Kindle Home (plugin KOReader)

> Objetivo: plugin KOReader (`kindlehome.koplugin`) tipo “homepage” para Kindle (KUAL + KOReader) con reloj/fecha, estado del dispositivo, clima (Open-Meteo) y **Hacker News vía `hnmd`** (`https://hnmd.miguehm.com/top`); lectura en Markdown (persistencia `.md` + render HTML en crengine).  
> Fuente técnica base: investigación 2026-11-15 sobre KOReader v2026.07.1 en `/usr/lib/koreader`.  
> Este documento es el **contrato de implementación** (fases, dependencias, criterios, riesgos y registros). **No iniciar implementación** fuera de lo que la fase activa autorice.

## 1) Estado, alcance y convenciones

- **Estado del repo:** F0–F4 implementadas en código (scaffold, dashboard offline, base transversal, lectura/persistencia base y clima Open-Meteo+geocoding con cache-first/stale); **pendientes verificación en Kindle real/runtime KOReader y registro en ledger** para cerrar F1–F4 (gates F1/F2/F3 no cerrados).
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
- `hnmd` entrega `markdown` por item (cuando `status == ok`) y `hn_url` siempre presente; `url` puede ser `null` (Ask HN).
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
  - HN/hnmd: `hnmd_enabled`, `hnmd_base_url` (default `https://hnmd.miguehm.com`), `hnmd_api_key`, `hnmd_max_items` (1–20), `hnmd_ttl_minutes`
  - Red: `http_timeout_s`, `http_max_bytes`, `refresh_budget_s` (presupuesto total por actualización)
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
- GET texto/JSON con `socketutil` timeouts, límite de bytes, `User-Agent`, y resultado tipado `{ok,status,body,headers?,error_kind}`.
- **Error kinds mínimos:** `timeout`, `network`, `http_401`, `http_503`, `http_other`, `parse`, `too_large`.
- Retries: solo para fallos transitorios de red/timeout (máx. 1 reintento corto) y **nunca** en bucle para `401`.
- Respetar presupuesto global de actualización (`refresh_budget_s`) y fetch secuencial por fuente para no congelar UI.

### 3.5 Logging y UX de errores (`lib/logger.lua` + UI)
- Log acotado y estructurado por módulo/evento (`http_fetch`, `cache_load`, `refresh_done`, etc.) sin secretos ni payloads sensibles.
- Usuario final: mensajes breves y accionables (“Offline, showing cached data”, “Invalid API key in Settings”, “hnmd server is starting, try again in a few minutes”).

### 3.6 Modelos de dominio normalizados (internos)
- `DashboardState`: hora, batería, red, clima, hn, errores/resumen de refresh, timestamps.
- `WeatherView`: actual, min/max, código WMO+texto, `place_name`, `observed_at/fetched_at`, `is_stale`.
- `HnItemView`: `id`, `rank`, `type`, `title`, `hn_url`, `url?`, `by`, `score`, `descendants`, `published_at`, `domain`, `markdown`, `status`, `error?`, `scraped_at`.
- `ArticleDoc`: metadatos + cuerpo MD + HTML renderizado + rutas de archivo.

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
- [ ] **5.1** Extender/confirmar config: `hnmd_enabled`, `hnmd_base_url` (default `https://hnmd.miguehm.com`), `hnmd_api_key`, `hnmd_max_items`, `hnmd_ttl_minutes`.
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

### Fase 6 — Digest y pulido de lectura
**Depende de:** Fases 4, 5
- [ ] **6.1** `lib/digest.lua`: modelo de portada diaria (hora, clima, top HN) + render MD/HTML.
- [ ] **6.2** Persistir `digest/YYYY-MM-DD.md/.html` y exponer “Open latest digest”.
- [ ] **6.3** Unificar estilos HTML/CSS para MuPDF (simple, legible en e-ink) entre dashboard/artículos/digest.
- [ ] **6.4** Mejoras de lectura: metadatos consistentes, estados vacíos, navegación de retorno predecible.
- [ ] **6.5** (Opcional) acción “Abrir en lector” para archivos generados, detrás de flag/config.

**Criterio de salida:** digest diario generado/abrible y lectura consistente entre fuentes disponibles.  
**Verificación:** generar digest con datos parciales (p.ej. solo clima o solo HN), reabrir, revisar render.

### Fase 7 — Ajustes completos, gestos y automatización
**Depende de:** Fases 4–6
- [ ] **7.1** Menú de ajustes completo: clima, HN, rutas, TTLs, refresh policy, toggles de secciones.
- [ ] **7.2** Dispatcher/documentación para gesto y Profiles (abrir al inicio / al despertar) con comportamiento seguro.
- [ ] **7.3** Política de refresh al abrir: cache-first + refresco condicionado por TTL/red/presupuesto; indicador de progreso breve.
- [ ] **7.4** Centralizar mensajes de error/estado en UI (sin stack traces, sin secretos).
- [ ] **7.5** Endurecer límites: tamaño máximo de payload, número de items por ciclo, timeout global de actualización.

**Criterio de salida:** flujo diario completo (abrir panel → ver estado → refrescar → leer) usable y predecible.  
**Verificación:** apertura automática/manual, offline/online, cancelación lógica por presupuesto (si aplica), reentrada de refresh.

### Fase 8 — Endurecimiento, validación en dispositivo y empaquetado
**Depende de:** Fase 7
- [ ] **8.1** Matriz de pruebas desktop + Kindle real (sin WiFi, WiFi inestable, 401/503, lat/lon inválida, caché corrupta, settings incompletos).
- [ ] **8.2** Revisar performance percibida en Kindle (tiempos de fetch/parse/render) y ajustar budgets/TTLs/defaults.
- [ ] **8.3** Revisión de seguridad/privacidad: enmascarado de key, no logs sensibles, documentación de almacenamiento local.
- [ ] **8.4** Documentación final: `README.md`, `CHANGELOG.md`, troubleshooting, configuración `hnmd_api_key` (UI y archivo), rutas de datos.
- [ ] **8.5** Empaquetado: zip instalable de `kindlehome.koplugin`, checklist de release, versión en `_meta.lua`.
- [ ] **8.6** (Opcional) fallback HN alternativo, i18n completa, userpatch/screensaver experimental.

**Criterio de salida:** MVP instalable, documentado y validado en dispositivo objetivo con fallos comunes controlados.  
**Verificación:** ejecución completa de matriz de pruebas y registro en ledger.

## 7) Matriz de verificación mínima (por fase)

> **Referencia:** la validación objetivo es **Kindle real** (e-ink/KOReader). Pruebas en desktop/PC son auxiliares y no sustituyen la verificación en Kindle.

- **F0–F1 (UI/local):** en Kindle: carga plugin, navegación básica, refresh, sin errores en log (desktop auxiliar opcional).
- **F2 (transversal):** timeout, HTTP 401/503/500 simulado o forzado, JSON inválido, caché corrupta, escritura atómica.
- **F3 (lectura):** render MD básico, escape HTML, persistencia `.md/.html`, apertura/cierre overlay, fallback navegación.
- **F4 (clima):** ubicación válida/inválida, geocoding OK/fail, online/offline, TTL expirado.
- **F5 (hnmd):** 200, 401, 503 `warming_up`, red caída, item sin markdown/error, Ask HN `url=null`.
- **F6–F7 (integración):** digest parcial/completo, refresh al abrir, gestos/profiles, reentrada.
- **F8 (dispositivo):** smoke + regresión en **Kindle real** y tiempos aceptables (obligatorio para cierre MVP).

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
| YYYY-MM-DD | F0/0.x | (ej.) Se cambió ruta de cache | (motivo) | (bajo/medio/alto) | ⏸ diferida / ✔ resuelta | (acción tomada o pendiente) |

## 10) Ledger de verificación (plantilla)

> Registrar cada ejecución relevante de verificación (por fase, regresión o pre-release).

| Fecha | Fase | Entorno | Qué se verificó | Resultado | Evidencia / notas | Flakes / pendientes |
|---|---|---|---|---|---|---|
| 2026-11-15 | Cambio de alcance (sin RSS) | Linux dev (repo) | Búsqueda `rss/RSS/FeedItemView/open_rss/articles/rss` en repo; revisión de `config.lua`, `paths.lua`, `README.md`, `PLAN.md` tras R1–R5 | PASS | `grep` sin coincidencias en `kindlehome.koplugin/README.md/AGENTS.md`; claves/rutas RSS removidas. Sin runtime KOReader en este entorno. | Gates previos siguen pendientes: verificación F1 en Kindle real y cierre/ledger F2 (§6 F1/F2) |
| 2026-11-15 | F3 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos nuevos/modificados F3 (`lib/render/md_to_html.lua`, `lib/article_store.lua`, `ui/actions.lua`, `ui/article_view.lua`, `ui/dashboard.lua`, `main.lua`, `lib/config.lua`); revisión de wiring y contratos (escape/sanitización básica links, atomic write, rutas internas, open_in_reader flag off) | PASS (sintaxis/wiring estático) | Sin runtime KOReader en entorno; no valida `UIManager/ScrollHtmlWidget/ReaderUI` en dispositivo. | Pendiente: verificación funcional F3 + gates F1/F2 en KOReader (Kindle objetivo) y registro de resultados |
| 2026-11-15 | F4 (impl. base) | Linux dev (repo) | Sintaxis Lua (`luac -p`) de módulos F4/nuevos o modificados (`lib/wmo.lua`, `lib/geocoding.lua`, `lib/weather.lua`, `lib/weather_state.lua`, `ui/menus.lua`, `ui/dashboard.lua`, `main.lua`) y revisión estática de contratos (cache-first/stale vía `refresh/cache`, uso de `lib/http`, presupuesto/reentrada, mensajes UI breves, sin secretos en logs) | PASS (sintaxis/wiring estático) | Sin runtime KOReader ni red real/Kindle en entorno; no valida Open-Meteo/geocoding en dispositivo, prompts WiFi, ni render/timings en e-ink. | Pendiente: verificación funcional F4 (ubicación válida/inválida, online/offline, TTL, caché vigente/expirada, geocoding OK/fail) y gates F1–F3 en KOReader (Kindle objetivo) |
| YYYY-MM-DD | F0 | KOReader desktop Linux / Kindle FW ... | Carga plugin, abrir/cerrar dashboard | PASS/FAIL | log, screenshot, pasos | (si aplica) |

## 11) Criterios de aceptación del MVP (definición de terminado)

- El plugin está enfocado y validado para **Kindle (KOReader, e-ink)**; no se considera objetivo de soporte PC/desktop.
- Dashboard abre desde menú/gesto en Kindle y muestra hora/fecha + estado básico + secciones disponibles.
- Clima y HN (`hnmd`) funcionan con **cache-first**, estados de error manejados y sin crashes offline.
- HN soporta `hnmd_api_key` por UI y por `settings/kindlehome.lua`, con manejo correcto de `200/401/503 warming_up` contra `https://hnmd.miguehm.com/top` (o `hnmd_base_url` configurada).
- Artículos HN y digest se pueden renderizar en overlay, persistir en `.md/.html` y reabrir.
- Configuración y rutas están documentadas; no se registran secretos en logs; caché corrupta se recupera automáticamente.
- Existe verificación registrada por fases críticas y **smoke/regresión en Kindle real** (obligatorio).