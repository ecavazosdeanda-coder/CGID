import '../../tenant/models/church_model.dart';

class MeetScheduler {
  /// Checks if any weekly service is currently active or starting soon (within `bufferMinutes`).
  /// Returns the `ServiceMeeting` if found, otherwise `null`.
  static ServiceMeeting? getActiveMeeting(
    ChurchModel church, {
    int bufferMinutes = 15,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    ServiceMeeting? active;
    DateTime? activeStart;
    for (final service in church.weeklyServices) {
      final daysUntil = (service.weekday - now.weekday + 7) % 7;
      final nextServiceDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: daysUntil));

      // Check this week's occurrence and the previous one. The previous
      // occurrence is required for meetings that cross midnight.
      for (final serviceDay in [
        nextServiceDay,
        nextServiceDay.subtract(const Duration(days: 7)),
      ]) {
        final start = DateTime(
          serviceDay.year,
          serviceDay.month,
          serviceDay.day,
          service.startTime.hour,
          service.startTime.minute,
        );
        var end = DateTime(
          serviceDay.year,
          serviceDay.month,
          serviceDay.day,
          service.endTime.hour,
          service.endTime.minute,
        );
        if (!end.isAfter(start)) {
          end = end.add(const Duration(days: 1));
        }

        final visibleFrom = start.subtract(Duration(minutes: bufferMinutes));
        if (!now.isBefore(visibleFrom) && now.isBefore(end)) {
          if (activeStart == null || start.isBefore(activeStart)) {
            active = service;
            activeStart = start;
          }
        }
      }
    }

    return active;
  }
}
