import 'package:flutter/material.dart';

/// Tipos de reunión litúrgica
enum ServiceType {
  recepcionSabado,
  escuelaSabatica,
  cultoMatutino,
  sociedadJuvenil,
  sociedadFemenil,
  cultoVespertino,
  oracionEntreSemana,
  estudioBiblico,
  ensayoAlabanza,
  otro,
}

/// Representa una reunión individual recurrente en la semana
class ServiceMeeting {
  final int weekday; // 1: Lunes ... 5: Viernes, 6: Sábado, 7: Domingo
  final TimeOfDay startTime; // Ej. 09:30
  final TimeOfDay endTime; // Ej. 10:45
  final String title; // 'Escuela Sabática'
  final ServiceType type;
  final String? customMeetUrl; // Sala específica para esta reunión si aplica

  const ServiceMeeting({
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.title,
    required this.type,
    this.customMeetUrl,
  });

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'start':
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
    'end':
        '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    'title': title,
    'type': type.name,
    'customMeetUrl': customMeetUrl,
  };

  factory ServiceMeeting.fromJson(Map<String, dynamic> json) {
    final startParts = (json['start'] as String).split(':');
    final endParts = (json['end'] as String).split(':');
    return ServiceMeeting(
      weekday: json['weekday'] as int,
      startTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      endTime: TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      ),
      title: json['title'] as String,
      type: ServiceType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ServiceType.otro,
      ),
      customMeetUrl: json['customMeetUrl'] as String?,
    );
  }
}

/// Modelo de Región Administrativa
class RegionModel {
  final String id; // 'region-15'
  final String name; // 'Región 15'
  final List<String> states; // ['Nuevo León', 'Tamaulipas']
  final String? presbyterName; // 'Pbro. Encargado de Región'

  const RegionModel({
    required this.id,
    required this.name,
    required this.states,
    this.presbyterName,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'states': states,
    'presbyterName': presbyterName,
  };

  factory RegionModel.fromJson(Map<String, dynamic> json) => RegionModel(
    id: json['id'] as String,
    name: json['name'] as String,
    states: List<String>.from(json['states'] ?? []),
    presbyterName: json['presbyterName'] as String?,
  );
}

/// Modelo de Iglesia Local
class ChurchModel {
  final String id; // 'mx-nl-mty-central'
  final String regionId; // 'region-15'
  final String name; // 'Iglesia de Dios en Monterrey (Templo Central)'
  final String state; // 'Nuevo León'
  final String city; // 'Monterrey'
  final String address; // 'Av. Francisco I. Madero #1234, Centro'
  final double latitude; // 25.686614
  final double longitude; // -100.316112
  final String googleMapsUrl; // 'https://maps.app.goo.gl/...'
  final String pastorName; // 'Pbro. Juan Pérez'
  final String defaultMeetUrl; // 'https://meet.google.com/xxx-yyyy-zzz'
  final String audioStreamUrl; // Transmisión de solo audio de bajo ancho de banda (ej. Icecast, Shoutcast, Radio)
  final List<ServiceMeeting> weeklyServices;
  final List<String> currentNotices;
  final bool isUnifiedServiceActive;

  const ChurchModel({
    required this.id,
    required this.regionId,
    required this.name,
    required this.state,
    required this.city,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.googleMapsUrl,
    required this.pastorName,
    required this.defaultMeetUrl,
    this.audioStreamUrl = '',
    required this.weeklyServices,
    this.currentNotices = const [],
    this.isUnifiedServiceActive = false,
  });

  ChurchModel copyWith({
    String? audioStreamUrl,
    List<ServiceMeeting>? weeklyServices,
    List<String>? currentNotices,
    bool? isUnifiedServiceActive,
  }) => ChurchModel(
    id: id,
    regionId: regionId,
    name: name,
    state: state,
    city: city,
    address: address,
    latitude: latitude,
    longitude: longitude,
    googleMapsUrl: googleMapsUrl,
    pastorName: pastorName,
    defaultMeetUrl: defaultMeetUrl,
    audioStreamUrl: audioStreamUrl ?? this.audioStreamUrl,
    weeklyServices: weeklyServices ?? this.weeklyServices,
    currentNotices: currentNotices ?? this.currentNotices,
    isUnifiedServiceActive:
        isUnifiedServiceActive ?? this.isUnifiedServiceActive,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'regionId': regionId,
    'name': name,
    'state': state,
    'city': city,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'googleMapsUrl': googleMapsUrl,
    'pastorName': pastorName,
    'defaultMeetUrl': defaultMeetUrl,
    'audioStreamUrl': audioStreamUrl,
    'weeklyServices': weeklyServices.map((s) => s.toJson()).toList(),
    'currentNotices': currentNotices,
    'isUnifiedServiceActive': isUnifiedServiceActive,
  };

  factory ChurchModel.fromJson(Map<String, dynamic> json) => ChurchModel(
    id: json['id'] as String,
    regionId: json['regionId'] as String,
    name: json['name'] as String,
    state: json['state'] as String,
    city: json['city'] as String,
    address: json['address'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    googleMapsUrl: json['googleMapsUrl'] as String? ?? '',
    pastorName: json['pastorName'] as String? ?? '',
    defaultMeetUrl: json['defaultMeetUrl'] as String? ?? '',
    audioStreamUrl: json['audioStreamUrl'] as String? ?? '',
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
  final String? regionId; // 'region-15'
  final String? churchId; // 'mx-nl-mty-central'
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String? locationName;
  final String? googleMapsUrl;
  final String? streamUrl;

  const ChurchEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.scope,
    this.regionId,
    this.churchId,
    required this.startDateTime,
    required this.endDateTime,
    this.locationName,
    this.googleMapsUrl,
    this.streamUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'scope': scope.name,
    'regionId': regionId,
    'churchId': churchId,
    'startDateTime': startDateTime.toIso8601String(),
    'endDateTime': endDateTime.toIso8601String(),
    'locationName': locationName,
    'googleMapsUrl': googleMapsUrl,
    'streamUrl': streamUrl,
  };

  factory ChurchEvent.fromJson(Map<String, dynamic> json) => ChurchEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    scope: EventScope.values.firstWhere(
      (value) => value.name == json['scope'],
      orElse: () => EventScope.local,
    ),
    regionId: json['regionId'] as String?,
    churchId: json['churchId'] as String?,
    startDateTime: DateTime.parse(json['startDateTime'] as String),
    endDateTime: DateTime.parse(json['endDateTime'] as String),
    locationName: json['locationName'] as String?,
    googleMapsUrl: json['googleMapsUrl'] as String?,
    streamUrl: json['streamUrl'] as String?,
  );
}
