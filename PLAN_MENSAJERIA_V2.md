# Plan de Desarrollo: Sistema de Mensajería Interna (CGDI v2)

## 1. Visión General y Reglas de Negocio

Este documento detalla la arquitectura y el flujo de trabajo para el módulo de mensajería interna, diseñado con un enfoque de "Mesa de Ayuda" y comunicación departamental.

### Reglas de Privacidad y Comunicación
1. **Directorio Restringido:** Los usuarios normales (músicos, proyeccionistas, colaboradores) solo pueden ver e iniciar chats con compañeros de **su misma iglesia**.
2. **Invisibilidad del Admin:** Los Administradores y Pastores Generales NO aparecen en el directorio de los usuarios normales. Un usuario normal no puede dar el primer paso para contactar a un Admin.
3. **Inicio por Admin:** Los Administradores pueden buscar a cualquier usuario de cualquier iglesia en su directorio global e iniciar una conversación.
4. **Cierre de Conversación:** El Administrador tiene un botón para "Cerrar" el chat. Al cerrarse, el usuario normal solo podrá leer el historial, pero ya no podrá enviar más mensajes.
5. **Redirección / Puenteo:** El Administrador puede "Añadir / Transferir" a un tercer usuario (de cualquier iglesia) a la conversación, creando un puente seguro de comunicación entre dos personas que originalmente no podían chatear entre sí.

---

## 2. Estructura de Base de Datos (Firestore)

### Colección: `chats`
Se ubicará en la raíz de Firestore para permitir chats cruzados entre iglesias cuando un Admin intervenga.

* **Documento (`chatId`)**
  * `type`: `string` ('direct' o 'group')
  * `participants`: `Array<string>` (Lista de UIDs con acceso a la conversación)
  * `status`: `string` ('open' o 'closed')
  * `createdBy`: `string` (UID del creador)
  * `lastMessage`: `string` (Texto del último mensaje para vista previa)
  * `lastMessageTime`: `timestamp`
  * `churchScope`: `string` (Opcional. ID de la iglesia si el chat es estrictamente local)

* **Subcolección: `messages`**
  * **Documento (`messageId`)**
    * `senderId`: `string` (UID de quien envía)
    * `text`: `string` (Contenido del mensaje)
    * `timestamp`: `timestamp` (Hora de envío)
    * `isSystemMessage`: `boolean` (Para mensajes automáticos como "El admin cerró el chat" o "Usuario X fue añadido")

---

## 3. Reglas de Seguridad (`firestore.rules`)

Las reglas blindarán la lógica de negocio a nivel de base de datos:

```javascript
match /chats/{chatId} {
  // LECTURA: Solo si tu UID está en 'participants' o eres Admin
  allow read: if isAuthenticated() && (request.auth.uid in resource.data.participants || isAdmin());

  // CREACIÓN: 
  // - Admins pueden crear con quien sea.
  // - Usuarios normales solo pueden crear si ambos participantes pertenecen al mismo 'churchId'.
  allow create: if isAuthenticated() && (
    isAdmin() || 
    isSameChurch(request.auth.uid, request.resource.data.participants)
  );

  // ACTUALIZACIÓN (Cerrar/Añadir participantes):
  // - Solo Admins pueden cambiar el estado a 'closed' o modificar 'participants'.
  allow update: if isAdmin();

  match /messages/{messageId} {
    // LECTURA: Hereda los permisos del chat padre
    allow read: if isAuthenticated() && request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants;

    // ESCRITURA: Solo si eres participante Y el estado del chat es 'open'
    allow create: if isAuthenticated() && 
                  request.auth.uid in get(/databases/$(database)/documents/chats/$(chatId)).data.participants &&
                  get(/databases/$(database)/documents/chats/$(chatId)).data.status == 'open' &&
                  request.resource.data.senderId == request.auth.uid;
  }
}
```

---

## 4. Interfaz de Usuario (UI) en el Dashboard

1. **Punto de Acceso:** Se añadirá un botón flotante (FAB) de 💬 en la esquina inferior derecha del `AdminDashboardScreen`.
2. **Bandeja de Entrada (Inbox):** Panel deslizable que muestra todos los chats donde el usuario es participante, ordenados por `lastMessageTime`.
3. **Nuevo Mensaje (Directorio):**
   * *Vista Admin:* Listado completo de usuarios agrupados por iglesia.
   * *Vista Usuario Normal:* Listado filtrado (solo compañeros de su iglesia, omitiendo perfiles con rol 'admin').
4. **Vista de Chat Activo:**
   * Burbujas de chat.
   * En la barra superior, si eres Admin, aparecerán dos botones extra: 
     * 🔒 **Cerrar Chat**
     * 🔀 **Añadir/Redirigir a otro miembro**

---

## 5. Próximos Pasos Técnicos para la Siguiente Sesión
1. Crear el modelo de datos en `lib/features/messaging/models/chat_model.dart`.
2. Crear los servicios de Firebase y Providers en `lib/features/messaging/providers/chat_provider.dart`.
3. Actualizar el archivo `firestore.rules`.
4. Construir la UI del widget `ChatOverlay` e inyectarlo en el `AdminDashboardScreen`.
