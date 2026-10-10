# Comentarios pastorales — V2 RC2

Biblia (la cita seleccionada), Puntos de Fe y cada publicación de Literatura
incluyen un botón discreto «Comentarios pastorales». El panel se abre a petición
y se cierra con «Ocultar comentarios». No añade comentarios a las proyecciones.

Todos, incluso invitados y usuarios de otras iglesias o regiones, pueden leer
todos los comentarios publicados para esa lectura. Los filtros de iglesia,
región, estado y ciudad son opcionales: inicialmente se muestran todos.
Los filtros geográficos usan el directorio de iglesias disponible; se ampliarán
al incorporar el archivo definitivo del directorio.

Los roles pastor y admin pueden escribir. El pastor solo gestiona sus propios
comentarios de su iglesia asignada. Administración puede editar, ocultar y
publicar cualquier comentario. Se requiere correo verificado para escribir.
Los comentarios pueden guardarse ocultos; son accesibles únicamente a su autor
pastoral asignado y a administración, según reglas de Firestore. No se eliminan
físicamente al ocultarlos. Texto plano de hasta 3000 caracteres.

Los documentos están bajo reading_comments/{tipo_hash}/comments/{id}. El ID
incluye tipo y SHA-256 del identificador estable de la lectura; cambiar su título
no cambia su conversación. En Biblia corresponde al intervalo seleccionado,
compartido entre las vistas de Biblia, referencias y atril.

No se publican correos electrónicos del autor. Se muestra su rol y procedencia.
Las suscripciones se abren solo al consultar el panel y se liberan al cerrarlo.
Firestore conserva su comportamiento de caché offline; los cambios de visibilidad
se reciben al sincronizar. La retirada no puede revocar copias ya leídas sin red.

Verificación: flutter test y flutter analyze; permisos reales contra emulador:

    firebase emulators:exec --project demo-cgid-comments --only firestore "node tool/test-reading-comment-rules.cjs"

El script se niega a usar servidores externos. Comprueba invitados, roles,
ocultación, autoría, iglesia asignada, validación de contenido y consultas.
