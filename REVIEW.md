- [x] Si falla, en lugar del documento real, crear un documento temporal donde aparezca la url, esto es para poder copiarla e ir a esa url manualmente, creo que se retornan esos detalles en la propia api
- [x] Remover digest
- [x] Al seleccionar weather, koreader crashea
- [x] Al seleccionar el directorio custom donde se guardan los post, koreader crashea
- [x] Formatee el link url de HN y de url source como un link y no como texto plano

Resuelto y verificado en Kindle PW5 en release 2.0.0 (Fase 14 de `PLAN.md`): link cards persistentes con `hn_url`/`url`/`content_error`, digest eliminado, fila de botones de menús sin huecos `nil`, coordenadas del clima persistidas, y enlaces `<a href>` en la meta del documento (dashboard sin cambios).

- [x] Resolver problemas con la interfaz, se ven elementos detras, en el area del titulo
- [x] Capacidad de especificar una carpeta custom donde se guarden los documentos descargados

Resuelto en release 2.1.0 (Fase 15 de `PLAN.md`): el Shell pinta ahora un fondo blanco opaco a pantalla completa, de modo que no se filtren los iconos de la pantalla anterior en la banda del título, y el `TitleBar` usa el Shell como destino de repintado. Nueva opción **Custom content folder** en Paths and storage: acepta rutas absolutas/anidadas (p. ej. `/mnt/us/My Docs/KindleHome`), rechaza relativas/`..` y el directorio de instalación de KOReader; si está vacía se mantienen `storage_mode`/`documents_subdir`. Los archivos ya descargados no se migran: permanecen en su carpeta anterior y se re-descargan al abrirlos. Verificado en repo con gates y smokes y **probado en Kindle PW5 (2026-11-16, confirmado por el usuario)**. Posteriormente se añadió en el mismo release 2.1.0 el selector nativo de carpetas (F15.4) y una opción Reset, aún pendiente de verificación en dispositivo.

- Que Kindle Home se abra directamente y el menú de configuraciones esté dentro de kindle home y no como otras opciones
