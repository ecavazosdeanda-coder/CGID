# CGID 2.0.0-rc.1 — distribución sin firma

Esta entrega candidata permite probar la versión 2.0 antes de adquirir y
configurar las firmas de cada tienda.

## Artefactos

- Android: APK instalable y AAB de archivo, firmados temporalmente con la clave
  de depuración. No deben publicarse en Google Play.
- Windows: instalador EXE y paquete ZIP portable sin certificado Authenticode.
- macOS: DMG sin certificado Developer ID ni notarización.
- iOS: aplicación compilada y comprimida para firma posterior. No es instalable
  en un dispositivo normal hasta contar con firma y perfil de aprovisionamiento.
- Linux: `tar.gz` experimental. Las funciones locales pueden probarse, pero
  Firebase Auth, Firestore, Storage y AI no tienen soporte oficial Flutter para
  Linux en las dependencias actuales.
- Web: PWA completa, que es la opción recomendada para usuarios Linux mientras
  se completa la capa nativa.

## Requisitos para la versión estable firmada

1. Crear un keystore de producción Android y guardarlo como secreto de CI.
2. Obtener Apple Developer, certificados iOS/macOS, perfiles y notarización.
3. Obtener un certificado Authenticode para Windows o publicar mediante
   Microsoft Store/MSIX.
4. Registrar las aplicaciones iOS y macOS en Firebase; actualmente sólo Android
   y Web tienen configuración Firebase nativa.
5. Para Linux, mantener la PWA como canal estable o sustituir Firebase por una
   API backend compatible y probar cada plugin nativo en Ubuntu LTS.

Nunca deben subirse certificados, keystores, contraseñas ni perfiles privados al
repositorio. Se almacenan como secretos cifrados del sistema de CI.
