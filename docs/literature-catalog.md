# Literatura con Drive y lectura interna

El catálogo visible viene de `literature` en Firestore, no del catálogo de assets.
Los cinco registros de demostración y los PDF originales están ocultos de esta
sección. Los archivos locales, Biblia, Puntos de Fe, himnos y corpus doctrinal
se conservan. La consulta de producción al implementar devolvió un catálogo vacío.

## Publicación por el administrador

1. Subir un archivo PDF a Drive, hasta 100 MB (recomendado: 20 MB o menos). No documentos nativos de Google Docs.
2. Compartir como lector con cualquier persona que tenga el enlace y permitir descarga.
3. En Administración/Literatura, usar Publicar Literatura y pegar el enlace.
4. La aplicación comprueba acceso y contenido PDF antes de guardar el registro.

Esta versión no sube desde la app a Drive: la subida y permisos se gestionan en
Drive por el administrador. Los lectores no necesitan abrir Drive, autenticarse
allí ni ver enlaces. La publicación usa UUID, evitando límites por títulos largos.
Se admiten URLs HTTPS directas de otros servidores si permiten CORS en web.

## Visor y descarga offline

El visor recibe bytes PDF por Drive API (files.get, alt=media), no usa iframe ni
redirección. Incluye búsqueda; Descargar para leer sin conexión solo está disponible
en aplicaciones instaladas. Desde RC2, web no ofrece descarga ni selección/copia
de texto y el servicio rechaza escrituras de caché PDF. No ofrece abrir
Drive, exportar, compartir, imprimir ni guardar en la carpeta Descargas.

La copia se almacena en Hive en las aplicaciones instaladas. Se lee primero esa
copia sin hacer llamadas a Drive. Web no lee copias guardadas por versiones previas.
La clave incluye ID y hash del enlace para no reutilizar otro archivo al cambiar
la publicación. Para publicar una revisión del PDF usar un archivo/enlace nuevo;
si se reemplaza el contenido bajo el mismo enlace, la copia offline anterior se
mantiene. Máximo de seguridad: 100 MB por documento. Por encima de 20 MB se pide
confirmación antes de publicar por el consumo de memoria y datos. La lectura
remota permite hasta tres minutos. No hay borrado automático de copias locales.

En web Literatura requiere conexión. La compilación usa --no-web-resources-cdn
y el SW conserva recursos de la interfaz, pero no PDF remotos. Desinstalar la app
nativa o borrar sus datos puede eliminar las copias descargadas. La publicación
oculta deja de mostrarse al reconectar;
sin conexión se muestra la última caché confirmada y una advertencia.

## Catálogo y errores

Quitar del catálogo marca hidden:true, conserva metadatos, PDF remoto y copias
locales; se replica a clientes conectados. Los snapshots confirmados reemplazan
el catálogo, incluido el servidor vacío. No se mezclan assets ni datos obsoletos.
Escrituras rechazadas no anuncian éxito ni borran registros locales. Un timeout
puede confirmarse después: revisar el catálogo antes de repetir la operación.

## Configuración y límites

Google Drive API está habilitada en cgdi-app-v2, cuya facturación sigue desactivada.
No se creó bucket ni se activó Blaze. Claves públicas de cliente en drive_api_config.dart:

- Web: exclusivamente drive.googleapis.com y referencias de los dos dominios de
  Hosting de la app y localhost para desarrollo.
- Nativa: exclusivamente drive.googleapis.com. Sin restricción de aplicación para
  compatibilidad móvil/escritorio; no autoriza archivos privados ni escrituras.

Se puede sobrescribir con --dart-define=LITERATURE_DRIVE_API_KEY=... . Estas claves
no son OAuth ni claves de cuenta de servicio. No modificar las claves de Firebase.
Para otro dominio, restringir/configurar una clave web apropiada. Revisar cuotas
para evitar abuso; no habilitar facturación o aumentos sin autorización.

La descarga es privada dentro de la experiencia de la app, NO DRM ni cifrado con
identidad: el archivo fuente está compartido por enlace. Quien obtenga ese enlace
fuera de la app puede leerlo. Un propietario del dispositivo puede inspeccionar
su almacenamiento. La aplicación no promete impedir extracción o capturas.

Fuentes oficiales:
- https://developers.google.com/workspace/drive/api/guides/manage-downloads
- https://developers.google.com/workspace/drive/api/guides/resource-keys
- https://developers.google.com/workspace/drive/api/guides/limits

La candidata v2.0.0-rc.2 compila estas funciones también en los paquetes nativos.
