import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  ChurchModel? church;
  
  // Attempt to load from Firestore
  try {
    if (churchId != null && churchId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance.collection('churches').doc(churchId).get(const GetOptions(source: Source.serverAndCache));
      if (doc.exists) {
        church = ChurchModel.fromJson(doc.data()!);
      }
    } else if (churchName != null && churchName.isNotEmpty) {
      final qs = await FirebaseFirestore.instance.collection('churches').where('name', isEqualTo: churchName).limit(1).get(const GetOptions(source: Source.serverAndCache));
      if (qs.docs.isNotEmpty) {
        church = ChurchModel.fromJson(qs.docs.first.data());
      }
    }
  } catch (e) {
    // Fallback to offline asset on failure
  }

  // Fallback to local asset
  if (church == null) {
    try {
      final jsonString = await rootBundle.loadString('assets/data/regions_and_churches.json');
      final data = jsonDecode(jsonString);
      final List<dynamic> churchesJson = data['churches'];
      final churches = churchesJson.map((e) => ChurchModel.fromJson(e)).toList();

      church = churches.firstWhere((c) => churchId != null && churchId.isNotEmpty ? c.id == churchId : c.name == churchName);
    } catch (_) {
      return null;
    }
  }

  // Fetch notices from the new subcollection
  try {
    final qs = await FirebaseFirestore.instance.collection('churches').doc(church.id).collection('notices').get(const GetOptions(source: Source.serverAndCache));
    final notices = qs.docs.map((d) => d.data()['title'] as String).toList();
    church = church.copyWith(currentNotices: notices);
  } catch (e) {
    // If we fail, just keep whatever was there
  }

  if (church != null && (churchId == null || churchId.isEmpty)) {
    await prefs.setString('selected_church_id', church.id);
  }
  
  return church;
});

final churchEventsProvider = FutureProvider<List<ChurchEvent>>((ref) async {
  try {
    final activeChurch = await ref.watch(tenantProvider.future);
    
    // Attempt Firestore first
    List<ChurchEvent> allEvents = [];
    try {
      final qs = await FirebaseFirestore.instance.collection('events').get(const GetOptions(source: Source.serverAndCache));
      allEvents = qs.docs.map((d) => ChurchEvent.fromJson(d.data())).toList();
    } catch (e) {
      // Fallback
      final jsonString = await rootBundle.loadString('assets/data/regions_and_churches.json');
      final data = jsonDecode(jsonString);
      final List<dynamic> rawEvents = data['events'] ?? [];
      allEvents = rawEvents.map((e) => ChurchEvent.fromJson(e)).toList();
    }

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
