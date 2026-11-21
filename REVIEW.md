- [x] Si falla, en lugar del documento real, crear un documento temporal donde aparezca la url, esto es para poder copiarla e ir a esa url manualmente, creo que se retornan esos detalles en la propia api
- [x] Remover digest
- [x] Al seleccionar weather, koreader crashea
- [x] Al seleccionar el directorio custom donde se guardan los post, koreader crashea
- [x] Formatee el link url de HN y de url source como un link y no como texto plano

Resuelto y verificado en Kindle PW5 en release 2.0.0 (Fase 14 de `PLAN.md`): link cards persistentes con `hn_url`/`url`/`content_error`, digest eliminado, fila de botones de menús sin huecos `nil`, coordenadas del clima persistidas, y enlaces `<a href>` en la meta del documento (dashboard sin cambios).

- [x] Resolver problemas con la interfaz, se ven elementos detras, en el area del titulo
- [x] Capacidad de especificar una carpeta custom donde se guarden los documentos descargados

Resuelto en release 2.1.0 (Fase 15 de `PLAN.md`): el Shell pinta ahora un fondo blanco opaco a pantalla completa, de modo que no se filtren los iconos de la pantalla anterior en la banda del título, y el `TitleBar` usa el Shell como destino de repintado. Nueva opción **Custom content folder** en Paths and storage: acepta rutas absolutas/anidadas (p. ej. `/mnt/us/My Docs/KindleHome`), rechaza relativas/`..` y el directorio de instalación de KOReader; si está vacía se mantienen `storage_mode`/`documents_subdir`. Los archivos ya descargados no se migran: permanecen en su carpeta anterior y se re-descargan al abrirlos. Verificado en repo con gates y smokes y **probado en Kindle PW5 (2026-11-16, confirmado por el usuario)**. Posteriormente se añadió en el mismo release 2.1.0 el selector nativo de carpetas (F15.4) y una opción Reset, aún pendiente de verificación en dispositivo.

- Que Kindle Home se abra directamente al seleccionarlo en las herramientas y el menú de configuraciones esté dentro de dashboard de kindle home
- Mostrar "feedback" de que el dashboard se está actualizando
- El icono de siguiente no se muestra correctamente
- No hay icono de regresar a la pagina anterior cuando se avanza a la pagina siguiente en hackernews widget

Implementado en release 2.4.0 (Fase 19 de `PLAN.md`), pendiente de verificación en Kindle PW5: Tools abre el dashboard sin submenú; los ajustes del plugin viven en un `TouchMenu` abierto desde el engranaje del dashboard; el hero muestra «Updating…» antes del refresco bloqueante; los iconos invertidos conservan su canal alpha (visibles en el pager y en la pestaña activa) y el pager de HN tiene flecha anterior con wrap simétrico (oculto con una sola página). Gates y smokes PASS en repo.

Corregido en release 2.4.1: en 2.4.0 el engranaje abría un recuadro diminuto porque `TouchMenu` interpreta cada entrada de `tab_item_table` como la lista de ítems misma, no como un descriptor con `item_table` anidado. El engranaje pasa ahora el array de secciones directamente como pestaña única; queda pendiente comprobar en PW5 que se despliega a lo ancho con las seis secciones.

- Mejorar la apariencia de la barra del título y los iconos de ajustes y salir: deben estar más a la derecha y mejor alineados.
- Evitar que los iconos de cambiar página del widget de Hacker News salten de posición cuando la última página tiene menos elementos.

Implementado en release 2.7.0 (Fase 22 de `PLAN.md`), pendiente de verificación visual en Kindle PW5: la cabecera usa márgenes simétricos con el cuerpo, centra verticalmente los iconos y emplea assets propios normalizados (`header/settings.svg`, `header/close.svg`). Top Stories absorbe el alto restante del viewport y ancla el paginador al fondo, de modo que las flechas conservan su posición aunque la última página tenga menos historias. Gates y smokes PASS en repo.

- que al volver a entrar a kh, recuerde en que numero de pagina me quedé en el widget de HN, regrese a la primera pagina cuando se haga refresh del contenido con el boton
- Poder definir la cantidad de items por pagina del widget de HN
