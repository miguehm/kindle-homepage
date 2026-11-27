# STYLES.md — Guía de estilos de implementación (KindleHome)

`DESIGN.md` define **qué** se ve (paleta, tipografía, componentes de "Paperwhite Monochrome").
Esta guía define **cómo** se construye en `kindlehome.koplugin/` para que se vea así en un
Kindle Paperwhite (PW5, 1236×1648, 300 PPI, Lua 5.1/LuaJIT) sin desperdiciar CPU ni refrescos
e-ink. Si algo choca con `AGENTS.md`, manda `AGENTS.md`.

Plan de adopción: `docs/internals/PLAN.md` §16 (fases 37–44).

---

## 1. Tokens: una sola fuente

Todos los valores visuales viven en `lib/render/theme.lua`. **Ningún widget escribe un número
mágico** de tamaño, padding, color o fuente.

| Grupo | Acceso | Valores (dp, antes de escalar) |
| --- | --- | --- |
| Espaciado | `Theme.space.*` | `xs 4` · `sm 8` · `md 12` · `gutter 16` · `margin 20` · `lg 24` · `xl 36` |
| Tamaños | `Theme.size.*` | `header_h 52` · `nav_h 52` · `icon 24` · `icon_sm 20` · `card_pad 12` · `rank_col 32` · `hit_min 48` · `section_gap 8` |
| Tipografía | `Theme.face(config, role)` | `display 32` · `headline_lg 26` · `headline_md 20` · `headline_sm 18` · `body_lg 17` · `body_md 15` · `body_sm 13` · `label_lg 14` · `label_md 12` · `label_sm 10` |
| Color | `Theme.color.*` | `fg #000` · `muted #666` · `hairline #E5E5E5` · `canvas #FFF` · `inverse_bg #000` / `inverse_fg #FFF` |

Reglas:
- **Rejilla de 4px.** Todo espaciado y tamaño es múltiplo de 4. Nada de 3, 5, 10, 14, 22 o 30.
- **Escalado.** Usa siempre `Theme.native_size(config, dp)`, que aplica `Screen:scaleBySize` y
  `ui_font_scale`. Nunca llames a `Screen:scaleBySize` directamente desde un widget.
- **Fuentes.** Serif (Noto Serif, en lugar de Literata) para contenido. Sans (Noto Sans, en lugar
  de Inter) para la interfaz: etiquetas, reloj, contadores, botones. Solo hay regular y bold:
  los pesos 500/600 se pintan en bold. Nunca uses `Font:getFace("cfont", n)` fuera de `theme.lua`.
- **Alturas de línea.** Pásalas siempre a través de `design_text.lua`: titulares 1.3, cuerpo 1.45.
- **Si falta un token, añádelo** a `theme.lua` antes de usarlo. Un acceso a un token inexistente
  (p. ej. `Theme.space.md` antes de F37) se convierte en 1dp sin avisar.

## 2. Color y forma

- Solo cuatro tonos discretos: negro, `#666`, `#E5E5E5` y blanco. Sin alfa, sin gradientes, sin
  grises intermedios inventados.
- **Esquinas rectas.** `radius =` está prohibido (lo comprueba `check_invariants.sh`).
- Bordes de 1px. Usa hairline `#E5E5E5` para contener y negro solo para modales, controles
  activos o avisos (`notice_box`).
- La jerarquía se consigue con peso, tamaño y espacio en blanco, no con más color.
- **Selección y presión = inversión binaria:** fondo negro y texto/icono blanco. Los iconos sobre
  fondo negro usan la variante `-inverse.svg`, con `alpha` activado.

## 3. Objetivos táctiles

- **Mínimo 48dp** (`Theme.size.hit_min`) por lado en todo control táctil. El dibujo puede ser
  más pequeño (icono de 20–24dp), pero el `dimen` del `TapIcon` es de 48dp y está centrado en él.
- Las filas (historias, tareas, menús) son táctiles en todo el ancho.
- Deja al menos `Theme.space.sm` entre dos controles táctiles contiguos.
- Lo que se dibuja como botón tiene que ser táctil en toda su superficie. Un cuadro negro de 30dp
  con un área táctil de 20dp es un bug.
- Las acciones destructivas (borrar) piden confirmación con `ConfirmBox` y nunca quedan junto a
  la acción principal sin separación.

## 4. Refresco e-ink: presupuesto por interacción

| Interacción | Presupuesto |
| --- | --- |
| Tap en un control | 1 `"fast"` en `control.dimen` (inversión), luego el cambio de la sección |
| Paginar historias o tareas | 1 rebuild de la tarjeta y 1 `"ui"` en la región de la tarjeta |
| Tick del reloj (cada minuto) | 0 rebuilds del body y 1 `"ui"` en `clock.dimen` |
| Refresh con contenido idéntico | 0 updates (la firma no cambia) |
| Cambio de pestaña | 1 `"ui"` de pantalla completa, 0 `full` |
| Abrir/cerrar la vista, rotación | `"full"` |
| Cada 8 updates `"ui"` | se promueve 1 a `"full"` (`UI_UPDATES_BEFORE_FULL = 8`) |

Reglas:
- **Siempre con región.** `UIManager:setDirty(widget, mode)` sin región está prohibido en
  widgets. Marca solo la sección que cambió.
- **`setDirty` solo sobre el top-level** (el `Shell`). Los hijos lo alcanzan con `show_parent`.
- Usa `"fast"` (A2/DU) solo para la inversión de presión, que es binaria y no tiene grises. Nunca
  la uses para texto con antialias ni para imágenes.
- **Highlight-then-act** mediante `ui/widget/press_feedback.lua`: invertir, `setDirty "fast"`,
  `forceRePaint`, ejecutar el callback en `nextTick` y quitar la inversión con `"ui"` si el
  control sigue en pantalla.
- Una operación bloqueante (red, descarga) muestra antes su indicador y llama a `forceRePaint`.
  Si no, el usuario no verá nada hasta que termine.

## 5. Coste de CPU: reglas de construcción

- **Un modelo y una firma por `show()`.** El `body_factory` recibe el modelo ya construido.
- La firma (`lib/ui_signature.lua`) se calcula **por sección** y sobre strings ya formateados,
  nunca sobre los payloads completos.
- **Reconstruye solo la sección cuya firma cambió.** Header y nav se reutilizan entre páginas.
- **La búsqueda de filas que caben** (binaria, medir antes de hacer scroll) se hace solo cuando
  cambia la clave de layout: pantalla, rotación, escala, filas preferidas o secciones visibles.
  Se mide con el peor caso (los títulos más largos del payload), de modo que filas por página y
  total de páginas no cambian al paginar.
- `ScrollableContainer` solo como último recurso medido (`if not chosen then`).
- **Llama a `:free()`** en los subárboles reemplazados.
- **Sin temporizadores en segundo plano.** El reloj se programa alineado al minuto y se cancela
  en `onCloseWidget`, `onSuspend` y al abrir un diálogo, menú o reader.
- Prefiere `paintRect` (batería, checkbox, divisores) a SVG para formas simples. Los SVG se piden
  siempre al mismo tamaño, para aprovechar la caché de `ImageWidget`.
- Mide en el dispositivo con `logger.timing` (solo en debug, sin secretos). Objetivo: paginar
  < 300 ms, tick de reloj < 50 ms.

## 6. Componentes (contratos de implementación)

| Componente | Archivo | Contrato |
| --- | --- | --- |
| Header | `ui/widget/dashboard_header.lua` | Banda de `header_h`. Título a la izquierda en el margen exterior. Estado (wifi, batería) e iconos ajustes/cerrar a la derecha, separados por `space.md`. Hairline debajo. Iconos desde `Theme.icon_file(..., "header", ...)`. |
| Tarjeta | `stories_card`, `todos_card` | `FrameContainer` con hairline y `card_pad`. Cabecera con badge invertido, título `label_lg` y acciones a la derecha. Pager anclado abajo con relleno (`apply_fill`). |
| Fila | `ui/widget/tap_row.lua` | Ancho completo. Divisor hairline inferior. Título `headline_sm`, 2 líneas como máximo con elipsis. Meta `label_md` en `muted`, con el formato `a · b · c`. |
| Pager | compartido | `Page N of M` a la izquierda. Botones prev/next en SVG con 48dp táctiles. El mismo componente en historias y tareas. |
| Checkbox | `ui/widget/checkbox.lua` | Cuadrado de 16dp con borde negro de 1px. Si está marcado, cuadrado interior de 10dp. Área táctil de 48dp. Se dibuja con `paintRect`. |
| Chip | `ui/widget/tag_chips.lua` | Sin seleccionar: borde hairline y texto `muted` `label_sm`. Seleccionado: relleno negro, borde negro y texto blanco. Etiqueta en formato `label: count`. |
| Aviso | `notice_box` | Borde negro de 1px, icono, texto `body_sm` y acción opcional "Retry". Uno solo por tarjeta. |
| Nav inferior | `ui/widget/bottom_nav.lua` | Celdas iguales de `nav_h`. La activa va invertida. Icono de 24dp con etiqueta `label_sm` en mayúsculas. |
| Toast | `InfoMessage` con `timeout` | 3–4 s. Una frase. Solo para confirmar acciones, no para estados persistentes. |

## 7. Estados

Cada sección resuelve sus cinco estados con el mismo patrón visual:

| Estado | Presentación |
| --- | --- |
| Cargando (refresh explícito) | Badge invertido `Updating…` en la cabecera de la tarjeta, como región pequeña. Los auto-refresh no muestran indicador. |
| Sin datos todavía | `Not loaded yet — tap ↻`. Nunca "unavailable" si no se intentó. |
| Vacío | Una línea centrada en `body_md` `muted` que diga qué filtro está activo. |
| Error / offline | `notice_box` con la causa breve y "Retry". |
| Desactualizado (stale) | El contenido se mantiene y `notice_box` indica la antigüedad ("Showing data from 2 h ago"). |

La frescura ("Updated 3 min ago") aparece **en un solo lugar** por pantalla.

## 8. Texto de interfaz (copy)

- **Toda la UI visible está en inglés.** Las cadenas viven en `ui/messages.lua` (o en `_()` en
  `menus.lua`). Nunca hay literales visibles dispersos en widgets.
- Sentence case en botones y mensajes ("Add task", "Due soon"). MAYÚSCULAS solo en etiquetas
  `label_sm` de la nav y en los badges.
- Sé breve y accionable: qué pasó y qué hacer ("Offline. Connect Wi-Fi and retry."). Sin stack
  traces, sin códigos HTTP crudos, sin payloads.
- **Nunca muestres ni registres la API key.** En la UI se enmascara por defecto.
- Separador de metadatos ` · `. Fechas cortas `27 Nov`. Hora 12/24 h según la configuración.
  Unidades con espacio (`12 km/h`, `342 pts`).

## 9. Lectura de artículos (HTML derivado)

- CSS solo en `em`. Serif, `line-height: 1.45`, negro sobre blanco y enlaces subrayados.
- **Sin `<img>`:** las imágenes se convierten en enlaces saneados con `sanitize_href`.
- Cabecera: un único `<h1>` y una línea de byline `domain · date · N pts`, sin bloques de
  metadatos técnicos.
- Fallback pager: tercio izquierdo para atrás, dos tercios derechos para adelante. Los enlaces
  tienen prioridad sobre el paso de página.

## 10. Checklist antes de un PR de UI

- [ ] Sin números mágicos: todo sale de `Theme.*` y está en la rejilla de 4px.
- [ ] Controles táctiles ≥ 48dp.
- [ ] Cada `setDirty` tiene región. `"fast"` solo para la inversión.
- [ ] Una interacción equivale a una sección reconstruida, como máximo. Se llama a `:free()` en lo
      reemplazado.
- [ ] Copy en inglés y centralizado en `ui/messages.lua`.
- [ ] Sin `radius =`, sin `ScrollHtmlWidget` y sin sintaxis Lua 5.2+.
- [ ] `./scripts/check_lua51.sh`, `./scripts/check_invariants.sh` y `./scripts/smoke_ui.sh` en
      verde.
- [ ] Ledger de verificación y desviaciones actualizado en `docs/internals/PLAN.md`.
- [ ] `DESIGN.md` actualizado si cambia algo visible.
