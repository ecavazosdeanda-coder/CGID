# Guía de Fase 7: QA, Seguridad y Despliegue v2

Este documento detalla la infraestructura de pruebas automatizadas, el protocolo de integración E2E, las medidas de hardening de seguridad y la estrategia de despliegue escalonado implementada para la versión 2 de **CGDI**.

---

## 1. Batería de Pruebas Automatizadas

### A. Pruebas Flutter (Frontend y Lógica de Negocio)
Ejecutar con:
```bash
flutter test
```

- **Lógica Litúrgica y Conflictos (`test/plan_notifier_conflict_test.dart` y `test/service_plan_projection_test.dart`):**
  - Recuperación íntegra de cultos, culto activo y revisiones desde almacenamiento local (`SharedPreferences`).
  - Detección de concurrencia optimista (`remoteRevision > localRevision`) para prevenir sobreescrituras en la nube.
  - Aislamiento estricto de notas privadas pastorales respecto a la proyección pública.
  - Asignación dinámica e independiente de roles por culto (`presidente`, `predicador`).

- **Control Remoto Unificado (`test/remote_command_handler_test.dart` y `test/cloud_remote_bridge_test.dart`):**
  - Desacoplamiento de comandos remotos (`next`, `prev`, `black`, `next_section`, `prev_section`, `jump`, `project_verse`).
  - Validación de coordenadas bíblicas completas (`b, c, vStart, vEnd`).
  - Generación de códigos de sesión de alta entropía (~50 bits) de 10 caracteres legibles sin confusión visual.

- **Panel Administrativo y Permisos (`test/user_management_panel_test.dart` y `test/user_profile_permissions_test.dart`):**
  - Renderizado reactivo de usuarios activos y documentos en `account_invitations` con distintivo visual.
  - Adaptación de textos de estado vacío según el rol del usuario (Administrador General vs. Pastor Local).
  - Verificación de la matriz de permisos por rol (`admin`, `pastor`, `colaborador`, `proyeccionista`, `musico`).

### B. Pruebas de Cloud Functions (`functions/test/cloud_functions.spec.ts`)
Ejecutar con:
```bash
cd functions
npm run test:functions
```
- **Protección del último Administrador:** Verificación de que el sistema rechaza la eliminación o degradación del único administrador existente (`failed-precondition`).
- **Restricción de roles pastorales:** Validación de que un pastor únicamente puede crear o invitar a roles locales (`colaborador`, `proyeccionista`, `musico`).
- **Invitaciones sin contraseña:** Comprobación de que usuarios sin contraseña inicial se canalizan a la colección `account_invitations`.
- **Aislamiento territorial:** Garantía de que un pastor no puede operar sobre iglesias distintas a su congregación asignada.

### C. Pruebas de Reglas de Seguridad en Emulador (`functions/test/firestore_rules.spec.ts`)
Ejecutar con:
```bash
firebase emulators:exec --only firestore "npm --prefix functions run test:rules"
```
- Matriz completa de lectura y escritura para cada rol en `churches`, `users`, `events`, `notices` y `plans`.
- Restricción estricta para que el pastor únicamente pueda alterar campos operativos de su iglesia (`weeklyServices`, `defaultMeetUrl`, `audioStreamUrl`).
- Prohibición de borrado de eventos por parte de colaboradores litúrgicos.

---

## 2. Protocolo de Pruebas de Integración E2E (Manual Guiada)

Para certificar el flujo completo de vida de un culto antes de cada versión:

1. **Paso 1: Creación del Culto en Casa (Pastor / Colaborador)**
   - Iniciar sesión con cuenta de Pastor o Colaborador en red doméstica.
   - Diseñar el orden del culto: seleccionar himnos, pasajes bíblicos y asignar presidente / predicador.
   - Agregar notas pastorales privadas a los himnos y temas.
   - Sincronizar el culto a la nube (verificar que el estado cambie a *Sincronizado*).
2. **Paso 2: Descarga y Apertura en Templo (Proyeccionista)**
   - En la cabina del templo, abrir la aplicación con cuenta de `proyeccionista`.
   - Verificar que el culto sincronizado aparece en la lista de cultos disponibles.
   - Cargar el culto y abrir la pantalla de **Proyección** (monitor secundario / proyector).
   - Constatar que las notas privadas **no** se proyectan al templo.
3. **Paso 3: Control Remoto en Tiempo Real (Dispositivo Móvil)**
   - En el proyector, pulsar *Control Remoto Móvil* y escanear el código QR o ingresar el código de sesión de 10 caracteres.
   - Navegar entre diapositivas (siguiente, anterior, blackout).
   - Verificar que el proyector y el celular se mantienen sincronizados sin desfase perceptible.
4. **Paso 4: Salida de Transmisión (OBS Studio)**
   - Abrir OBS y agregar una fuente de navegador hacia `http://localhost:port/#/stream-overlay` o el overlay web en la nube.
   - Constatar que las diapositivas proyectadas se reflejan con fondo transparente y estilo broadcast.
5. **Paso 5: Resiliencia ante Pérdida de Red (Offline Fallback)**
   - Desconectar la conexión a internet en la computadora de proyección.
   - Navegar el culto completo: himnario, biblia, puntos de fe y partituras.
   - Constatar que ningún error bloquea la proyección gracias a la caché local y assets offline.
   - Reconectar internet y verificar la reanudación del estado sin pérdida de datos.

---

## 3. Checklist de Seguridad y Hardening

- [ ] **Rotación de API Key histórica de Google Drive (X4):**
  - Ingresar a [Google Cloud Console - Credenciales](https://console.cloud.google.com/apis/credentials).
  - Localizar la API Key previamente expuesta en el historial antiguo.
  - Eliminar la clave o regenerarla asegurando que ninguna compilación activa la requiera (v2 ya no depende de Drive para música/datos).
- [ ] **Restricción de API Keys por Dominio:**
  - En la clave web de Firebase (`AIzaSy...`), configurar restricciones de aplicaciones:
    - `HTTP referrers`:
      - `https://cgdi.org/*`
      - `https://*.cgdi.org/*`
      - `https://cgdi-app-v2.web.app/*`
      - `https://cgdi-app-v2.firebaseapp.com/*`
      - `http://localhost:*` (solo para entornos de prueba locales)
  - Restringir las APIs autorizadas para la clave únicamente a:
    - *Firebase Authentication API*
    - *Cloud Firestore API*
    - *Cloud Functions API*
- [ ] **Configuración de App Check:**
  - En Firebase Console, activar **Firebase App Check**:
    - **Web:** Proveedor reCAPTCHA Enterprise o reCAPTCHA v3 con dominios autorizados.
    - **Android:** Proveedor Play Integrity.
  - Activar el modo de cumplimiento (*Enforcement*) en Cloud Firestore y Cloud Functions tras verificar la ausencia de solicitudes legítimas bloqueadas.

---

## 4. Procedimiento de Despliegue Escalonado

### Fase 1: Proyecto de Staging / Canal de Vista Previa
1. Compilar y publicar las reglas y funciones al entorno de pre-producción:
   ```bash
   firebase deploy --only firestore:rules,functions
   ```
2. Publicar una vista previa de Hosting temporal:
   ```bash
   flutter build web --release --base-href /
   firebase hosting:channel:deploy pre-release-v2
   ```
3. Ejecutar las pruebas manuales guiadas sobre la URL generada.

### Fase 2: Respaldo y Migración de Datos
1. Exportar la base de datos de producción completa a Cloud Storage:
   ```bash
   gcloud firestore export gs://cgdi-backups-bucket/pre-v2-migration/
   ```
2. Ejecutar script de verificación de perfiles huérfanos o invitaciones pendientes heredadas.

### Fase 3: Publicación en Producción (`cgdi-app-v2`)
1. Desplegar reglas y funciones:
   ```bash
   firebase deploy --only firestore:rules,functions --project cgdi-app-v2
   ```
2. Desplegar Hosting en canal de producción:
   ```bash
   firebase deploy --only hosting --project cgdi-app-v2
   ```

### Fase 4: Periodo de Estabilización y Monitoreo (7 días)
- Supervisar métricas en Firebase Crashlytics y Google Cloud Monitoring.
- Monitorear logs de error de las Cloud Functions (`adminCreateUser`, `adminDeleteUser`, `adminUpdateRole`).
- Confirmar que ninguna regla de Firestore registre picos inusuales de `PERMISSION_DENIED` que puedan indicar desajustes en clientes locales.
- Al término del 7° día sin incidencias críticas, declarar la versión 2.0 como estable.
