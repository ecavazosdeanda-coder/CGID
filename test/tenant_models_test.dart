import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/features/tenant/models/church_model.dart';

void main() {
  test('church and weekly services survive JSON round trip', () {
    const original = ChurchModel(
      id: 'mx-nl-test',
      regionId: 'region-15',
      name: 'Iglesia de prueba',
      state: 'Nuevo León',
      city: 'Monterrey',
      address: 'Calle 123',
      latitude: 25.68,
      longitude: -100.31,
      googleMapsUrl: 'https://maps.google.com/',
      pastorName: 'Pbro. Prueba',
      defaultMeetUrl: 'https://meet.google.com/test-room',
      audioStreamUrl: 'https://stream.zeno.fm/f3wvbbqmdg8uv',
      weeklyServices: [
        ServiceMeeting(
          weekday: DateTime.saturday,
          startTime: TimeOfDay(hour: 9, minute: 30),
          endTime: TimeOfDay(hour: 10, minute: 45),
          title: 'Escuela Sabática',
          type: ServiceType.escuelaSabatica,
          customMeetUrl: 'https://meet.google.com/sabbath-room',
        ),
      ],
      currentNotices: ['Aviso de prueba'],
      isUnifiedServiceActive: true,
    );

    final restored = ChurchModel.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.regionId, original.regionId);
    expect(restored.audioStreamUrl, 'https://stream.zeno.fm/f3wvbbqmdg8uv');
    expect(restored.weeklyServices.single.weekday, DateTime.saturday);
    expect(restored.weeklyServices.single.startTime.hour, 9);
    expect(restored.weeklyServices.single.startTime.minute, 30);
    expect(restored.weeklyServices.single.type, ServiceType.escuelaSabatica);
    expect(restored.currentNotices, ['Aviso de prueba']);
    expect(restored.isUnifiedServiceActive, isTrue);
  });

  test('church event survives JSON round trip', () {
    final original = ChurchEvent(
      id: 'event-1',
      title: 'Confraternidad',
      description: 'Evento regional',
      scope: EventScope.regional,
      regionId: 'region-15',
      startDateTime: DateTime(2026, 10, 10, 10),
      endDateTime: DateTime(2026, 10, 10, 18),
      locationName: 'Templo Bethel',
    );

    final restored = ChurchEvent.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.scope, EventScope.regional);
    expect(restored.regionId, 'region-15');
    expect(restored.startDateTime, original.startDateTime);
    expect(restored.endDateTime, original.endDateTime);
  });
}
