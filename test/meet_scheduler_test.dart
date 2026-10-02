import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/features/meet_service/services/meet_scheduler.dart';
import 'package:cgid/features/tenant/models/church_model.dart';

ChurchModel churchWith(List<ServiceMeeting> meetings) => ChurchModel(
  id: 'church-test',
  regionId: 'region-test',
  name: 'Iglesia de prueba',
  state: 'Nuevo León',
  city: 'Monterrey',
  address: 'Dirección de prueba',
  latitude: 25.0,
  longitude: -100.0,
  googleMapsUrl: '',
  pastorName: '',
  defaultMeetUrl: 'https://meet.google.com/test-room',
  weeklyServices: meetings,
);

void main() {
  const saturdayService = ServiceMeeting(
    weekday: DateTime.saturday,
    startTime: TimeOfDay(hour: 11, minute: 0),
    endTime: TimeOfDay(hour: 13, minute: 0),
    title: 'Culto Matutino',
    type: ServiceType.cultoMatutino,
  );

  test('meeting becomes visible exactly at the configured buffer', () {
    final active = MeetScheduler.getActiveMeeting(
      churchWith([saturdayService]),
      at: DateTime(2026, 10, 3, 10, 45),
    );

    expect(active, same(saturdayService));
  });

  test('meeting is no longer active at its exact end time', () {
    final active = MeetScheduler.getActiveMeeting(
      churchWith([saturdayService]),
      at: DateTime(2026, 10, 3, 13),
    );

    expect(active, isNull);
  });

  test('meeting that crosses midnight remains active the following day', () {
    const overnight = ServiceMeeting(
      weekday: DateTime.friday,
      startTime: TimeOfDay(hour: 23, minute: 30),
      endTime: TimeOfDay(hour: 1, minute: 0),
      title: 'Vigilia',
      type: ServiceType.otro,
    );

    final active = MeetScheduler.getActiveMeeting(
      churchWith([overnight]),
      at: DateTime(2026, 10, 3, 0, 30),
    );

    expect(active, same(overnight));
  });

  test('meeting on another day is not reported as active', () {
    final active = MeetScheduler.getActiveMeeting(
      churchWith([saturdayService]),
      at: DateTime(2026, 10, 1, 11, 30),
    );

    expect(active, isNull);
  });
}
