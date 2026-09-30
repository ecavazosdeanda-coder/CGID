# Audios del himnario

`catalog.json` enlaza IDs estables de canto con archivos MP3 incluidos en la aplicación.
Ejecutar `tool/import_hymn_audio.ps1` desde PowerShell para importar la carpeta HIMNARIO.
Los originales se conservan. `import_report.json` lista los cantos sin grabación.

## Seguimiento de letra y editor de tiempos

`timings.json` tiene schemaVersion 1 y tiempos en milisegundos. Cada pista conserva
el nombre original y SHA-256 para identificar la grabación exacta que se sincronizará.
`timingStatus: pending` y `cues: []` significan que aún no se ha sincronizado.
El controlador expone `position` y `duration` del reproductor real.

Cada cue tiene `startMs`, `endMs`, `sectionIndex` y `lineIndex`
(índices desde cero de las secciones y líneas de la letra). Las repeticiones podrán
referirse a la misma línea con distintos tiempos. No se generan tiempos estimados.

El importador conserva cues cuyo ID y SHA-256 coincidan. La pantalla del canto
permite marcar líneas y silencios mientras suena el audio, deshacer y guardar.
Las marcas locales se conservan en preferencias del dispositivo, asociadas al ID,
SHA-256 y letra exacta. Cancelar restaura la secuencia anterior. La reproducción
resalta la línea activa y la muestra en un panel; no hay tiempos automáticos.
Las grabaciones todavía requieren marcado y revisión auditiva individual.
