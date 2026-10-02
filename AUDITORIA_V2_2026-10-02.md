# Auditoría funcional y técnica de CGDI v2

Fecha de corte: 2 de octubre de 2026
Rama revisada: `dev-v2`
Versión de aplicación: `2.0.0+16`

## Canales publicados verificados

| Canal | URL | Resultado HTTP |
| --- | --- | --- |
| v1 espejo Firebase | https://cgid-4c078.web.app | 200 |
| v1 producción GitHub Pages | https://ecavazosdeanda-coder.github.io/CGID/ | 200 |
| v2 Firebase Hosting | https://cgdi-app-v2.web.app | 200 |

La inspección visual de v2 confirmó que la portada carga correctamente y la consola del navegador no reportó errores ni advertencias durante el arranque.

## Validación ejecutada

- `flutter analyze --no-pub`: sin problemas.
- `flutter test --no-pub`: 25 pruebas aprobadas.
- `flutter build web --release --base-href / --no-pub --no-wasm-dry-run`: compilación correcta.
- `firebase deploy --only firestore:rules --dry-run --project cgdi-app-v2`: reglas compiladas correctamente y no publicadas.

## Estado frente al Plan Maestro v2

| Grupo | Capacidad | Estado | Evidencia / límite actual |
| --- | --- | --- | --- |
| 1 | Modularización | Parcial | Existen módulos `features/`, pero `workspace.dart` todavía concentra gran parte de la interfaz y coordinación. |
| 1 | PWA y modo sin conexión | Implementado parcial | Hay manifiesto y `sw.js`; falta una prueba automatizada de primer arranque, actualización y reconexión sin red. |
| 1 | Partituras OSMD diferidas | Implementado | El visor carga OSMD al abrir la partitura, no durante el arranque principal. |
| 1 | Control remoto web | Implementado con refuerzo local pendiente de publicar | Firestore, QR y control móvil existen. Los códigos ahora usan entropía criptográfica, 10 caracteres, esquema estricto y caducidad de 8 horas. |
| 1 | Transiciones de proyección | Implementado | La salida y overlays usan transiciones; se conserva sincronización con el orden de culto. |
| 2 | Selector multi-tenant | Implementado | Selección local por región/iglesia y persistencia en dispositivo. |
| 2 | Google Meet inteligente | Implementado | Selecciona reuniones según horario; depende de URLs y horarios correctos por iglesia. |
| 2 | Literatura/PDF | Implementado parcial | Catálogo local, caché y catálogo Firestore existen. Los enlaces/archivos deben ser publicados y revisados por administración. |
| 2 | Boletín PDF | Implementado y probado | La prueba verifica membrete y exclusión de notas privadas. |
| 2 | Favoritos y notas | Implementado | Persistencia local; no hay sincronización entre dispositivos. |
| 3 | Acceso ministerial | Implementado con refuerzo local pendiente de publicar | Auth por correo, roles y asignación. Se corrigió el alta por invitación y se bloqueó el panel si falta un perfil autorizado. |
| 3 | Planificador y nube | Implementado parcial | Crear/editar/proyectar y subir/bajar funciona; falta resolución explícita de conflictos entre dos editores simultáneos. |
| 3 | Atril digital | Implementado parcial | Lectura, acordes y transposición existen; el pedal Bluetooth requiere validación física por plataforma. |
| 3 | Web Push | Parcial | Permiso, notificación local y handlers del service worker existen; falta suscripción push/FCM y servicio programador de avisos. |
| 4 | Asistente doctrinal/litúrgico | Implementado parcial | Maneja API Key en memoria, reintentos y errores seguros. Sigue siendo prompt guiado, no RAG verificable con citas a los 32 Puntos de Fe y RVR 1909. |
| 4 | OBS / lower thirds | Implementado | Rutas `/overlay`, `/lowerthirds` y `/obs-dock`, más cliente OBS WebSocket. Requiere prueba con OBS real. |
| 4 | Audio de bajo ancho de banda | Parcial | El reproductor y estimación de datos existen; falta un origen de streaming de audio configurado y monitoreado. |
| 4 | CI/CD | Implementado para validación | `v2_ci.yml` analiza, prueba y compila la PWA en `dev-v2`; publicar a Firebase continúa siendo una acción deliberada. |

## Correcciones aplicadas durante esta auditoría

1. El alta ministerial usa correo verificado, `account_invitations/{email}` y una transacción: conocer una dirección invitada ya no basta para apropiarse de la cuenta, autoproclamarse pastor ni entrar al panel sin perfil.
2. El panel administrativo espera la validación del perfil y muestra acceso no autorizado si el documento no existe.
3. Las consultas de pastores ahora se filtran en Firestore por su iglesia; ya no se descargan perfiles ni correos de otras congregaciones para filtrarlos solo en pantalla.
4. El control remoto abandonó códigos predecibles de seis caracteres; usa códigos criptográficos de diez caracteres, caducidad y validación de esquema en Firestore.
5. Se retiró una API Key de Google Drive incrustada en el código. La clave publicada anteriormente debe rotarse o restringirse en Google Cloud.
6. La versión declarada se alineó con v2 y se añadió CI específica para `dev-v2`.

## Orden recomendado de trabajo

1. Publicar y probar las nuevas reglas de Firestore en un proyecto de pruebas; luego desplegarlas en `cgdi-app-v2`.
2. Rotar/restringir la antigua API Key de Drive, porque haberla retirado del código no la elimina del historial ni de compilaciones ya publicadas.
3. Migrar cualquier invitación antigua guardada como documento suelto en `users` a `account_invitations`.
4. Añadir pruebas de reglas con Firebase Emulator Suite para roles, invitaciones, aislamiento por iglesia y control remoto.
5. Incorporar control de revisiones/conflictos al sincronizar órdenes de culto.
6. Implementar RAG doctrinal con fragmentos y citas verificables; no presentar una respuesta generativa como doctrina oficial sin fuente.
7. Completar Web Push con FCM/suscripción y el backend programador; configurar y medir el origen real de audio ligero.
8. Validar OBS, pedal Bluetooth, PWA sin red y flujo pastor→proyeccionista en dispositivos reales antes de declarar v2 estable.

## Criterio de salida para v2 estable

No promover `dev-v2` a producción principal hasta que: las reglas desplegadas pasen pruebas de emulador, dos cuentas de iglesias distintas no puedan cruzar datos, un pastor pueda invitar y activar una cuenta desde cero, el orden creado en un equipo llegue y se proyecte desde otro, y exista una prueba completa con OBS y pérdida temporal de red.
