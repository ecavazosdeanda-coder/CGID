# 🏛️ PLAN MAESTRO DE ARQUITECTURA Y DESARROLLO: ECOSISTEMA CGID 2.0
> **Documento Rector y Especificación Técnica para el Equipo de Desarrollo**  
> **Sistema:** Biblioteca, Proyección y Plataforma Eclesial Multi-Tenant  
> **Organización:** Conferencia General de la Iglesia de Dios  
> **Línea Base:** CGID v1.0 (Producción Web Estable)  
> **Fecha de creación/actualización:** Octubre 2026  

> **Estado de ejecución (2 de octubre de 2026):** la v2 ya está publicada en
> `https://cgdi-app-v2.web.app` y continúa en estabilización sobre `dev-v2`.
> La matriz verificable de funciones completas, parciales y pendientes está en
> [`AUDITORIA_V2_2026-10-02.md`](AUDITORIA_V2_2026-10-02.md). Las instrucciones
> históricas de “no publicar” de este documento se conservan como referencia de
> la fase inicial y ya no describen el estado operativo actual.

---

## 📑 ÍNDICE GENERAL
1. [Contexto del Proyecto y Diagnóstico de v1.0](#1-contexto-del-proyecto-y-diagnóstico-de-v10)
2. [Protocolo de Seguridad y Entorno de Pruebas (Zero-Risk)](#2-protocolo-de-seguridad-y-entorno-de-pruebas-zero-risk)
3. [Estructura Organizacional Multi-Tenant (Regiones, Templos y Eventos)](#3-estructura-organizacional-multi-tenant-regiones-templos-y-eventos)
4. [Aprovechamiento del Ecosistema Google & Gemini IA Pro](#4-aprovechamiento-del-ecosistema-google--gemini-ia-pro)
5. [Estrategia de Migración de Datos (Legacy v1.0 a v2.0)](#5-estrategia-de-migración-de-datos-legacy-v10-a-v20)
6. [Desglose Detallado de los 4 Grupos de Implementación](#6-desglose-detallado-de-los-4-grupos-de-implementación)
7. [Modelos de Datos Formales (Código Dart)](#7-modelos-de-datos-formales-código-dart)
8. [Nueva Arquitectura Modular del Código (`lib/`)](#8-nueva-arquitectura-modular-del-código-lib)
9. [Dependencias Clave a Incorporar (`pubspec.yaml`)](#9-dependencias-clave-a-incorporar-pubspecyaml)
10. [Guía de Arranque para la Siguiente Sesión / Desarrollador](#10-guía-de-arranque-para-la-siguiente-sesión--desarrollador)

---

## 1. CONTEXTO DEL PROYECTO Y DIAGNÓSTICO DE v1.0

### 1.1 ¿Qué es CGID?
Es el software oficial de biblioteca sagrada (Biblia Reina-Valera 1909, Himnario Oficial de más de 500 himnos, 32 Puntos de Fe oficiales, Partituras digitales en MusicXML) y sistema de proyección multimedia para la **Conferencia General de la Iglesia de Dios**.

### 1.2 Estado de Distribución Actual (v1.0)
* **Canal Primario:** Web alojada en GitHub Pages: `https://ecavazosdeanda-coder.github.io/CGID/`
* **Canales Secundarios:** Instaladores de escritorio (Windows EXE, macOS DMG) y APK Android firmado localmente (sin Play Store debido a que las cuentas comerciales de firma de tiendas están pendientes de pago/autorización).
* **Condición Clave:** La versión web actual está activa y en uso por la hermandad. **NO DEBE ALTERARSE NI ROMPERSE.**

### 1.3 Diagnóstico Técnico y Cuellos de Botella de v1.0
* **Monolito en `lib/main.dart` (~4,217 líneas):** Concentra UI, lógica de negocio, manejo de proyección, llamadas a audio, controladores de texto a voz (TTS) y configuración de temas. Requiere modularización urgente mediante *Feature-First*.
* **Limitación de Control Remoto en Web:** El servidor HTTP local (`remote_server_io.dart`) solo funciona en aplicaciones de escritorio compiladas; en la web no puede abrir sockets TCP de escucha.
* **Modelo Monotemplo:** La v1.0 fue concebida como aplicación local para una sola computadora en un solo templo. No contempla la gestión de múltiples iglesias locales ni coordinación regional.

---

## 2. PROTOCOLO DE SEGURIDAD Y ENTORNO DE PRUEBAS (ZERO-RISK)

Para garantizar que el desarrollo de la v2.0 jamás desestabilice la v1.0 que usan los hermanos:

```
┌────────────────────────────────────────────────────────┐
│                   PRODUCCIÓN (INTACTO)                 │
│  URL: https://ecavazosdeanda-coder.github.io/CGID/     │
│  • Rama Git: 'main' / Tag: 'v1.0.0-production'         │
│  • NO TOCAR hasta aprobación final de la v2.0.         │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│             STAGING / PRUEBAS PRIVADAS (NUEVO)         │
│  • Rama Git: 'dev-v2' o 'feature/v2-regional-platform' │
│  • Pruebas Locales Wi-Fi: http://192.168.x.x:8080      │
│  • Pruebas en Nube Oculta: cgid-preview.web.app        │
└────────────────────────────────────────────────────────┘
```

### Reglas de Operación:
1. **Ramas Protegidas:** Todo el desarrollo nuevo se realizará en la rama `dev-v2`. La rama `main` queda bloqueada.
2. **Pruebas Locales Multi-Dispositivo (PC y Celular):**
   * Ejecutar en terminal: `flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0`
   * Desde cualquier celular o tablet conectado a la misma red Wi-Fi del desarrollador, se ingresa a la IP local (ejemplo: `http://192.168.1.75:8080`). Esto permite probar la experiencia móvil real sin publicar en internet.
3. **Canal de Vista Previa Aislado (Staging Web):**
   * Para pruebas con pastores o miembros del equipo fuera de la red local, se utilizará un subdominio o canal de vista previa (ejemplo: Firebase Hosting Preview Channel o Vercel) completamente desvinculado del dominio principal de GitHub Pages.

---

## 3. ESTRUCTURA ORGANIZACIONAL MULTI-TENANT (REGIONES, TEMPLOS Y EVENTOS)

La Conferencia General se compone de múltiples congregaciones distribuidas geográfica y administrativamente.

```
                      CONFERENCIA GENERAL (NACIONAL)
                                    │
       ┌────────────────────────────┴────────────────────────────┐
       ▼                                                         ▼
 REGIÓN 15 (Ej. Nuevo León y Tamaulipas)                  OTRAS REGIONES (1 a 14, 16+)
       │
       ├─► Iglesia de Dios en Monterrey (Templo Bethel)
       ├─► Iglesia de Dios en San Nicolás de los Garza
       ├─► Iglesia de Dios en Reynosa, Tamaulipas
       └─► Iglesia de Dios en Matamoros, Tamaulipas
```

### 3.1 Identidad y Ubicación Física de cada Iglesia
Cada congregación local registrada en el sistema contiene:
* **Identificador único (`id`):** ej. `mx-nl-mty-bethel`.
* **Región administrativa:** ej. `region-15`.
* **Ubicación Física:** Dirección completa, ciudad, estado, código postal.
* **Geolocalización GPS:** Latitud y longitud exactas.
* **Integración con Navegadores de Mapas:** Botón *"Cómo llegar"* que dispara deep-links nativos hacia **Google Maps**, **Waze** o **Apple Maps**.

### 3.2 Horarios de Culto Reales (Múltiples Reuniones)
El sistema no asume un único culto sabático, sino un esquema completo:

#### A. Cultos de Sábado:
1. **Recepción de Sábado (Viernes):** 19:30 – 21:00 hrs.
2. **Escuela Sabática (Estudio doctrinal):** 09:30 – 10:45 hrs.
3. **Culto Matutino (Alabanza y Predicación):** 11:00 – 13:00 hrs.
4. **Sociedad de Jóvenes / Femenil / Infantil:** 16:30 – 17:45 hrs.
5. **Culto Vespertino y Despedida de Sábado:** 18:00 – 19:30 hrs.

#### B. Actividades Entre Semana:
* **Martes:** Reunión de Oración y Testimonios (19:30 hrs).
* **Miércoles:** Estudio Bíblico / Discipulado (19:30 hrs).
* **Jueves:** Ensayo de Coro / Grupo de Alabanza (19:00 hrs).

### 3.3 Niveles de Eventos y Filtrado Inteligente
El calendario muestra avisos y eventos según el contexto del usuario:
* **Nacional:** Asambleas Generales, Convocatorias Nacionales (visible para toda la hermandad en el mundo).
* **Regional:** Confraternidades juveniles, campamentos o talleres de la Región (visible solo para las iglesias de esa Región).
* **Local:** Aniversarios de templo, bodas, campañas evangelísticas locales (visible para los miembros de ese templo específico).

---

## 4. APROVECHAMIENTO DEL ECOSISTEMA GOOGLE & GEMINI IA PRO

El plan **Gemini IA Pro (Google One AI Premium / Google Workspace con Gemini)** resuelve tres necesidades críticas de infraestructura con **$0 costo adicional**:

### 4.1 Google Meet Profesional para los Cultos en Vivo
* **Sin límite de 60 minutos:** Videollamadas de hasta **24 horas continuas**, eliminando cortes en servicios largos o vigilias.
* **Capacidad ampliada:** Salas con capacidad para 250 a 500 participantes conectados simultáneamente.
* **Grabación Directa en la Nube:** Grabación automática de cultos hacia Google Drive con opción de transcripción de texto en tiempo real.
* **Cancelación de Ruido Inteligente:** Filtrado de ruido ambiente y reverberación del templo para audio claro en las transmisiones.

### 4.2 Almacenamiento en la Nube de 2 Terabytes (Google Drive)
* Alojamiento de la **Biblioteca Digital de Literatura**: libros oficiales, revistas, folletos doctrinales y lecciones de Escuela Sabática en PDF.
* Repositorio de grabaciones de cultos pasados para la sección *"Cultos Anteriores"* en la app.

### 4.3 API de Gemini Pro (Google AI Studio)
* **Ventana de Contexto Gigante (hasta 2 millones de tokens):** Permite cargar en memoria simultáneamente toda la Biblia RVR 1909, el himnario completo y los 32 Puntos de Fe.
* **Asistente Litúrgico para Pastores:** El ministro escribe el tema de su predicación y Gemini Pro sugiere 3 himnos acordes del himnario oficial de CGID y pasajes de lectura bíblica complementarios.
* **Asistente Doctrinal RAG:** Búsqueda en lenguaje natural para la hermandad, restringida con prompts de sistema estrictos para responder **únicamente** con base en los 32 Puntos de Fe de la Iglesia de Dios y la Biblia RVR 1909.

---

## 5. ESTRATEGIA DE MIGRACIÓN DE DATOS (LEGACY v1.0 a v2.0)

Para garantizar una transición sin pérdida de datos locales:
1. **Migración de `servicePlan` y Caché Local:** 
   * En la v1.0, el programa de cultos se almacena mediante `SharedPreferences` o en variables estáticas de sesión. En la v2.0, todo plan de culto se persistirá en `Hive CE` vinculado a un `church_id`.
   * En el primer arranque de la v2.0, se correrá un script de migración que detecta si hay un culto guardado en `SharedPreferences` y lo moverá al formato de `ServicePlan` local.
2. **Assets Base (Offline First):**
   * Los archivos críticos como `assets/library_content_v6.json` (Biblia, Himnario, Puntos de Fe) se seguirán empaquetando junto a la app base para asegurar que en zonas rurales siempre haya acceso inmediato, incluso sin nube.

---

## 6. DESGLOSE DETALLADO DE LOS 4 GRUPOS DE IMPLEMENTACIÓN

### Grupo 1: Mejoras de Funciones Actuales (Pulido y Rendimiento v1.0)
* **Modularización de `main.dart`:** Dividir el monolito en arquitectura por capas y módulos (`features/`).
* **PWA Web-First de Alto Nivel:**
  * `manifest.json` completo con soporte para instalación en pantalla de inicio en Android y iOS sin pasar por tiendas.
  * `ServiceWorker` avanzado para almacenamiento en caché local (IndexedDB) de himnos, biblia y doctrina, permitiendo funcionamiento 100% offline.
* **Optimización de Partituras (OSMD):** Carga diferida (`lazy-load`) de la librería `opensheetmusicdisplay.min.js` (1.3 MB) para acelerar la apertura inicial de la aplicación.
* **Puente de Control Remoto para Web:** Implementación de fallback por WebSockets/WebRTC para permitir el control de diapositivas desde celulares cuando la proyección corre en navegador.
* **Transiciones de Proyección:** Añadir fundido suave (`fade transitions`) entre versículos e himnos para una proyección más estética en el proyector.

### Grupo 2: Implementaciones Básicas (Valor Inmediato para la Hermandad)
* **Selector de Iglesia Local:** Pantalla de bienvenida / selector con buscador por Región, Estado y Ciudad. Recuerda la selección en el dispositivo sin exigir inicio de sesión.
* **Botón Inteligente de Google Meet:**
  * Detección automática del culto activo según el día y la hora.
  * Apertura en 1 clic de la sala de Meet de la iglesia local (o del Meet Nacional si hay convocatoria general).
* **Módulo de Literatura y Documentos (v1):**
  * Catálogo clasificado: *Puntos de Fe explicados*, *Escuela Sabática*, *Estudios Doctrinales*, *Revistas Oficiales*.
  * Lector PDF integrado (`pdfrx`) con búsqueda de texto y opción de descarga sin conexión.
* **Boletín Litúrgico Compartible:** Generación con 1 clic de un PDF elegante del orden del culto con membrete del templo local, listo para compartir por WhatsApp.
* **Favoritos y Notas Personales:** Guardado local de himnos preferidos y notas personales de sermones.

### Grupo 3: Implementaciones Intermedias (Gestión Pastoral y Músicos)
* **Panel Web del Pastor/Administrador (`/admin`):**
  * Acceso seguro por correo/contraseña para ministros y obreros locales.
  * Configuración del enlace de Google Meet y horarios de cultos del templo.
  * Publicación de avisos locales semanales.
  * Planificador semanal de cultos con guardado en la nube.
  * Cuenta de **Colaborador Litúrgico** para hermanos autorizados que ayudan a preparar y sincronizar órdenes sin recibir facultades pastorales.
  * Las funciones de **Presidente** y **Predicador** se asignan por culto, no como cargos permanentes de la cuenta; una misma persona puede desempeñar funciones diferentes en reuniones distintas.
* **Sincronización en la Nube de Cultos (Cloud Sync):** El pastor diseña el culto desde su hogar y el proyeccionista en el templo lo carga instantáneamente en la pantalla principal.
  * El orden público y las notas privadas ministeriales se guardan en documentos separados. Las notas requieren una cuenta asignada a la iglesia.
* **Modo Atril Digital para Músicos:**
  * Cifrado y acordes sobre las letras de los himnos.
  * Transposición de tonos en tiempo real semitono a semitono (+/-).
  * Soporte de avance de diapositiva mediante pedales Bluetooth (PageFlip / AirTurn).
* **Notificaciones Web Push:** Recordatorios 15 minutos antes del inicio del culto para unirse a la sala de Google Meet.

### Grupo 4: Implementaciones Avanzadas (Tecnología de Punta)
* **Asistente Doctrinal y Litúrgico con Gemini Pro API:** Integración del asistente inteligente para pastores y miembros dentro de la aplicación.
* **Salida de Letras para Transmisión en Vivo (Lower Thirds / OBS Studio):** Endpoint `/overlay` con fondo transparente y animaciones suaves para superponer las letras de los cantos sobre las cámaras en transmisiones de video.
* **Transmisión de Audio de Bajo Ancho de Banda:** Canal de solo audio para hermanos en zonas con internet inestable o datos móviles limitados (consumo de solo 15-20 MB por servicio).
* **Pipelines de Despliegue Automatizado (CI/CD):** Flujos en GitHub Actions listos para cuando se adquieran las licencias de Google Play y Apple Store.

---

## 7. MODELOS DE DATOS FORMALES (CÓDIGO DART)

Crea estos modelos dentro del directorio `lib/features/tenant/models/`:

```dart
import 'package:flutter/material.dart';

/// Tipos de reunión litúrgica
enum ServiceType {
  recepcionSabado, escuelaSabatica, cultoMatutino, sociedadJuvenil,
  sociedadFemenil, cultoVespertino, oracionEntreSemana, estudioBiblico,
  ensayoAlabanza, otro
}

/// Representa una reunión individual recurrente en la semana
class ServiceMeeting {
  final int weekday;              // 1: Lunes ... 5: Viernes, 6: Sábado, 7: Domingo
  final TimeOfDay startTime;      // Ej. 09:30
  final TimeOfDay endTime;        // Ej. 10:45
  final String title;             // 'Escuela Sabática'
  final ServiceType type;
  final String? customMeetUrl;    // Sala específica para esta reunión si aplica

  const ServiceMeeting({
    required this.weekday, required this.startTime, required this.endTime,
    required this.title, required this.type, this.customMeetUrl,
  });

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'start': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
    'end': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    'title': title, 'type': type.name, 'customMeetUrl': customMeetUrl,
  };

  factory ServiceMeeting.fromJson(Map<String, dynamic> json) {
    final startParts = (json['start'] as String).split(':');
    final endParts = (json['end'] as String).split(':');
    return ServiceMeeting(
      weekday: json['weekday'] as int,
      startTime: TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1])),
      endTime: TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
      title: json['title'] as String,
      type: ServiceType.values.firstWhere((e) => e.name == json['type'], orElse: () => ServiceType.otro),
      customMeetUrl: json['customMeetUrl'] as String?,
    );
  }
}

/// Modelo de Región Administrativa
class RegionModel {
  final String id;                // 'region-15'
  final String name;              // 'Región 15'
  final List<String> states;      // ['Nuevo León', 'Tamaulipas']
  final String? presbyterName;    // 'Pbro. Encargado de Región'

  const RegionModel({
    required this.id, required this.name, required this.states, this.presbyterName,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'states': states, 'presbyterName': presbyterName,
  };

  factory RegionModel.fromJson(Map<String, dynamic> json) => RegionModel(
    id: json['id'] as String, name: json['name'] as String,
    states: List<String>.from(json['states'] ?? []),
    presbyterName: json['presbyterName'] as String?,
  );
}

/// Modelo de Iglesia Local
class ChurchModel {
  final String id;                // 'mx-nl-mty-central'
  final String regionId;          // 'region-15'
  final String name;              // 'Iglesia de Dios en Monterrey (Templo Central)'
  final String state;             // 'Nuevo León'
  final String city;              // 'Monterrey'
  final String address;           // 'Av. Francisco I. Madero #1234, Centro'
  final double latitude;          // 25.686614
  final double longitude;         // -100.316112
  final String googleMapsUrl;     // 'https://maps.app.goo.gl/...'
  final String pastorName;        // 'Pbro. Juan Pérez'
  final String defaultMeetUrl;    // 'https://meet.google.com/xxx-yyyy-zzz'
  final List<ServiceMeeting> weeklyServices;
  final List<String> currentNotices;
  final bool isUnifiedServiceActive;

  const ChurchModel({
    required this.id, required this.regionId, required this.name, required this.state,
    required this.city, required this.address, required this.latitude,
    required this.longitude, required this.googleMapsUrl, required this.pastorName,
    required this.defaultMeetUrl, required this.weeklyServices,
    this.currentNotices = const [], this.isUnifiedServiceActive = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'regionId': regionId, 'name': name, 'state': state, 'city': city,
    'address': address, 'latitude': latitude, 'longitude': longitude,
    'googleMapsUrl': googleMapsUrl, 'pastorName': pastorName,
    'defaultMeetUrl': defaultMeetUrl,
    'weeklyServices': weeklyServices.map((s) => s.toJson()).toList(),
    'currentNotices': currentNotices, 'isUnifiedServiceActive': isUnifiedServiceActive,
  };

  factory ChurchModel.fromJson(Map<String, dynamic> json) => ChurchModel(
    id: json['id'] as String, regionId: json['regionId'] as String,
    name: json['name'] as String, state: json['state'] as String,
    city: json['city'] as String, address: json['address'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    googleMapsUrl: json['googleMapsUrl'] as String? ?? '',
    pastorName: json['pastorName'] as String? ?? '',
    defaultMeetUrl: json['defaultMeetUrl'] as String? ?? '',
    weeklyServices: (json['weeklyServices'] as List? ?? [])
        .map((s) => ServiceMeeting.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
    currentNotices: List<String>.from(json['currentNotices'] ?? []),
    isUnifiedServiceActive: json['isUnifiedServiceActive'] as bool? ?? false,
  );
}

/// Niveles de Evento
enum EventScope { local, regional, nacional }

/// Modelo de Eventos y Convocatorias
class ChurchEvent {
  final String id;
  final String title;
  final String description;
  final EventScope scope;
  final String? regionId;         // 'region-15'
  final String? churchId;         // 'mx-nl-mty-central'
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String? locationName;
  final String? googleMapsUrl;
  final String? streamUrl;

  const ChurchEvent({
    required this.id, required this.title, required this.description,
    required this.scope, this.regionId, this.churchId,
    required this.startDateTime, required this.endDateTime,
    this.locationName, this.googleMapsUrl, this.streamUrl,
  });
}
```

---

## 8. NUEVA ARQUITECTURA MODULAR DEL CÓDIGO (`lib/`)

```text
lib/
├── core/
│   ├── config/                     # Temas visuales, estilos Glass, constantes de marca
│   ├── network/                    # Conexiones HTTP, WebSockets, Supabase/Firebase
│   ├── storage/                    # Hive CE, IndexedDB, SharedPreferences
│   ├── services/                   # AudioHandler, TTS, wakelock, projection manager
│   └── utils/                      # Formateadores, helpers sabáticos, lanzador de URLs
│
├── features/
│   ├── tenant/                     # Gestión de Regiones e Iglesias Locales
│   │   ├── models/church_model.dart
│   │   ├── data/church_repository.dart
│   │   ├── providers/tenant_provider.dart
│   │   └── presentation/church_selector_dialog.dart
│   │
│   ├── meet_service/               # Lógica inteligente de Google Meet
│   │   ├── services/meet_scheduler.dart
│   │   └── presentation/live_meet_card.dart
│   │
│   ├── literature/                 # Biblioteca de literatura y documentos
│   │   ├── models/document_model.dart
│   │   ├── data/literature_catalog.json
│   │   └── presentation/literature_screen.dart
│   │
│   ├── ai_assistant/               # Asistente Gemini IA Pro
│   │   ├── services/gemini_service.dart
│   │   └── presentation/doctrinal_ai_dialog.dart
│   │
│   ├── hymnal/                     # Himnario, acordes y partituras OSMD
│   ├── bible/                      # Texto bíblico RVR 1909
│   ├── faith/                      # 32 Puntos de Fe oficiales
│   ├── projection/                 # Pantalla de proyector, salidas HDMI y overlays
│   │
│   └── admin/                      # Panel para Pastores y Administradores
│       ├── presentation/admin_dashboard_screen.dart
│       ├── presentation/service_builder_screen.dart
│       └── presentation/notices_editor_screen.dart
│
└── main.dart                       # Entrada limpia: arranque de servicios y ruteador
```

---

## 9. DEPENDENCIAS CLAVE A INCORPORAR (`pubspec.yaml`)

Para la fase 2.0, estas dependencias se agregarán progresivamente:

| Paquete | Versión Recomendada | Propósito |
| :--- | :--- | :--- |
| `flutter_riverpod` | `^2.6.1` | Gestión de estado reactiva, modular y testeable. |
| `google_generative_ai`| `^0.4.6` | SDK oficial de Google para conectar con la API de Gemini Pro. |
| `go_router` | `^14.6.2` | Enrutamiento declarativo con URLs limpias para web (`/himnario`, `/literatura`, `/admin`). |
| `intl` | `^0.20.1` | Formateo localizado de fechas, horas y días sabáticos en español. |
| `supabase_flutter` | `^2.8.3` | *(Opcional)* Base de datos en tiempo real gratuita con RLS para cultos y avisos. |

---

## 10. GUÍA DE ARRANQUE PARA LA SIGUIENTE SESIÓN / DESARROLLADOR

Cuando un desarrollador (humano o inteligencia artificial) abra este proyecto para empezar a codificar, **debe seguir estrictamente este flujo de trabajo**:

### Paso 1: Asegurar el Entorno Git (Protección Zero-Risk)
Asegurarse de inicializar git, aislar la v1.0 y cambiar a la rama de desarrollo nueva:
```bash
git init
git add .
git commit -m "Respaldando producción v1.0"
git tag -a v1.0.0-stable -m "Versión 1.0 estable"
git checkout -b dev-v2
```

### Paso 2: Crear el Archivo Semilla (Regiones e Iglesias)
Generar el archivo base `assets/data/regions_and_churches.json` utilizando la estructura descrita en la Sección 7. Empezar poblando datos prueba reales de la **Región 15** (Nuevo León y Tamaulipas).

### Paso 3: Extraer Modelos Core
Crear la ruta `lib/features/tenant/models/` y guardar el código de `ChurchModel`, `RegionModel`, `ServiceMeeting`, etc.

### Paso 4: Selector y Banner Google Meet
Construir en la interfaz principal (antes de refactorizar el 100% de `main.dart`, como prueba de concepto) el modal de selección de iglesia y el widget reactivo del botón de Meet que lea la hora actual y determine qué evento litúrgico mostrar.

### Paso 5: Correr Servidor Local de Pruebas
Nunca publicar a producción en esta fase. Validar corriendo el Web Server de Flutter y conectándose desde un dispositivo móvil vía Wi-Fi:
```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
```

---
*Documento aprobado y validado. Sirve como fuente de verdad absoluta para el desarrollo de CGID v2.0.*
