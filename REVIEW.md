- [x] Si falla, en lugar del documento real, crear un documento temporal donde aparezca la url, esto es para poder copiarla e ir a esa url manualmente, creo que se retornan esos detalles en la propia api
- [x] Remover digest
- [x] Al seleccionar weather, koreader crashea
- [x] Al seleccionar el directorio custom donde se guardan los post, koreader crashea
- [x] Formatee el link url de HN y de url source como un link y no como texto plano

Resuelto y verificado en Kindle PW5 en release 2.0.0 (Fase 14 de `PLAN.md`): link cards persistentes con `hn_url`/`url`/`content_error`, digest eliminado, fila de botones de menús sin huecos `nil`, coordenadas del clima persistidas, y enlaces `<a href>` en la meta del documento (dashboard sin cambios).

- Resolver problemas con la interfaz, se ven elementos detras, en el area del titulo
- Capacidad de especificar una carpeta custom donde se guarden los documentos descargados
