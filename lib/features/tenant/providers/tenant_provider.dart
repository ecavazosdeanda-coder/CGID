import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/church_model.dart';

final tenantProvider = FutureProvider<ChurchModel?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final churchId = prefs.getString('selected_church_id');
  final churchName = prefs.getString('tenant_church_name');
  if ((churchId == null || churchId.isEmpty) &&
      (churchName == null || churchName.isEmpty)) {
    return null;
  }

  try {
    final jsonString = await rootBundle.loadString(
      'assets/data/regions_and_churches.json',
    );
    final data = jsonDecode(jsonString);
    final List<dynamic> churchesJson = data['churches'];
    final churches = churchesJson.map((e) => ChurchModel.fromJson(e)).toList();

    var church = churches.firstWhere(
      (c) => churchId != null && churchId.isNotEmpty
          ? c.id == churchId
          : c.name == churchName,
    );
    if (churchId == null || churchId.isEmpty) {
      await prefs.setString('selected_church_id', church.id);
    }
    final localNotices = prefs.getStringList('local_notices_${church.id}');
    if (localNotices != null) {
      church = church.copyWith(currentNotices: localNotices);
    }
    final customAudio = prefs.getString('custom_audio_stream_${church.id}');
    if (customAudio != null && customAudio.trim().isNotEmpty) {
      church = church.copyWith(audioStreamUrl: customAudio.trim());
    }
    final customMeet = prefs.getString('custom_meet_url_${church.id}');
    if (customMeet != null && customMeet.trim().isNotEmpty) {
      church = church.copyWith(defaultMeetUrl: customMeet.trim());
    }
    return church;
  } catch (e) {
    return null;
  }
});

/// Proveedor de Eventos y Convocatorias filtrados según la iglesia/región seleccionada
final churchEventsProvider = FutureProvider<List<ChurchEvent>>((ref) async {
  try {
    final activeChurch = await ref.watch(tenantProvider.future);
    final jsonString = await rootBundle.loadString(
      'assets/data/regions_and_churches.json',
    );
    final data = jsonDecode(jsonString);
    final List<dynamic> rawEvents = data['events'] ?? [];
    final allEvents = rawEvents.map((e) => ChurchEvent.fromJson(e)).toList();

    // Filtrado contextual:
    // 1. Siempre se muestran los eventos de alcance Nacional.
    // 2. Si hay iglesia activa, se agregan los Regionales de su región.
    // 3. Si hay iglesia activa, se agregan los Locales de esa iglesia específica.
    return allEvents.where((evt) {
      if (evt.scope == EventScope.nacional) return true;
      if (activeChurch == null) return false;
      if (evt.scope == EventScope.regional) {
        return evt.regionId == activeChurch.regionId;
      }
      if (evt.scope == EventScope.local) {
        return evt.churchId == activeChurch.id;
      }
      return false;
    }).toList()
      ..sort((a, b) => a.startDateTime.compareTo(b.startDateTime));
  } catch (e) {
    return [];
  }
});
