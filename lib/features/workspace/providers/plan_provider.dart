import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../content.dart';

class PlanState {
  final List<Entry> plan;
  final String activePlan;
  final Map<String, dynamic> savedPlans;
  final bool isSyncing;

  const PlanState({
    required this.plan,
    required this.activePlan,
    required this.savedPlans,
    this.isSyncing = false,
  });

  PlanState copyWith({
    List<Entry>? plan,
    String? activePlan,
    Map<String, dynamic>? savedPlans,
    bool? isSyncing,
  }) {
    return PlanState(
      plan: plan ?? this.plan,
      activePlan: activePlan ?? this.activePlan,
      savedPlans: savedPlans ?? this.savedPlans,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

final planProvider = NotifierProvider<PlanNotifier, PlanState>(
  () => PlanNotifier(),
);

class PlanNotifier extends Notifier<PlanState> {
  SharedPreferences? _prefs;

  @override
  PlanState build() {
    return const PlanState(
      plan: [],
      activePlan: 'Culto del sábado',
      savedPlans: {},
    );
  }

  void init(SharedPreferences prefs) {
    _prefs = prefs;
    Map<String, dynamic> savedPlans = {};
    String activePlan = 'Culto del sábado';
    List<Entry> plan = [];

    try {
      savedPlans = jsonDecode(prefs.getString('plans') ?? '{}');
      activePlan = prefs.getString('activePlan') ?? activePlan;
      plan = [
        for (final e in savedPlans[activePlan] ?? [])
          Entry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {}

    state = PlanState(
      plan: plan,
      activePlan: activePlan,
      savedPlans: savedPlans,
    );
  }



  Future<void> syncToCloud(String churchId) async {
    if (churchId.isEmpty) return;
    state = state.copyWith(isSyncing: true);
    try {
      final db = FirebaseFirestore.instance;
      await db
          .collection('churches')
          .doc(churchId)
          .collection('plans')
          .doc('weekly_plans')
          .set({
        'plans': state.savedPlans,
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception(
          'Tiempo de espera agotado. Verifica que Cloud Firestore esté creado y habilitado en la consola de Firebase.',
        ),
      );
      debugPrint('Cultos sincronizados a la nube para $churchId');
    } catch (e) {
      debugPrint('Error sincronizando a la nube: $e');
      rethrow;
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> fetchFromCloud(String churchId) async {
    if (churchId.isEmpty) return;
    state = state.copyWith(isSyncing: true);
    try {
      final db = FirebaseFirestore.instance;
      final doc = await db
          .collection('churches')
          .doc(churchId)
          .collection('plans')
          .doc('weekly_plans')
          .get()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw Exception(
              'Tiempo de espera agotado. Verifica que Cloud Firestore esté creado y habilitado en la consola de Firebase.',
            ),
          );

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final cloudPlans = Map<String, dynamic>.from(data['plans'] ?? {});
        _prefs?.setString('plans', jsonEncode(cloudPlans));
        
        final newPlan = [
          for (final e in cloudPlans[state.activePlan] ?? [])
            Entry.fromJson(Map<String, dynamic>.from(e)),
        ];

        state = state.copyWith(
          savedPlans: cloudPlans,
          plan: newPlan,
        );
        debugPrint('Cultos descargados de la nube para $churchId');
      }
    } catch (e) {
      debugPrint('Error descargando de la nube: $e');
      rethrow;
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  void setActivePlan(String name) {
    if (_prefs != null) {
      _prefs!.setString('activePlan', name);
    }
    final newPlan = [
      for (final e in state.savedPlans[name] ?? [])
        Entry.fromJson(Map<String, dynamic>.from(e)),
    ];
    state = state.copyWith(activePlan: name, plan: newPlan);
  }

  void saveAs(String name, {List<Entry>? entries}) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;
    final plan = List<Entry>.from(entries ?? state.plan);
    final newSavedPlans = Map<String, dynamic>.from(state.savedPlans)
      ..[normalizedName] = plan.map((e) => e.toJson()).toList();
    _prefs?.setString('plans', jsonEncode(newSavedPlans));
    _prefs?.setString('activePlan', normalizedName);
    state = state.copyWith(
      activePlan: normalizedName,
      plan: plan,
      savedPlans: newSavedPlans,
    );
  }

  void createPlan(String name) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;
    if (state.savedPlans.containsKey(normalizedName)) {
      setActivePlan(normalizedName);
      return;
    }
    saveAs(normalizedName, entries: const []);
  }

  void updatePlan(List<Entry> newPlan) {
    final plan = List<Entry>.from(newPlan);
    state = state.copyWith(plan: plan);
    _saveCurrentPlan(plan);
  }

  void addEntry(Entry entry) {
    final newPlan = List<Entry>.from(state.plan)..add(entry);
    updatePlan(newPlan);
  }

  void removeEntry(int index) {
    if (index < 0 || index >= state.plan.length) return;
    final newPlan = List<Entry>.from(state.plan)..removeAt(index);
    updatePlan(newPlan);
  }

  void insertEntry(int index, Entry entry) {
    final newPlan = List<Entry>.from(state.plan);
    final safeIndex = index.clamp(0, newPlan.length);
    newPlan.insert(safeIndex, entry);
    updatePlan(newPlan);
  }

  void replaceEntry(int index, Entry entry) {
    if (index < 0 || index >= state.plan.length) return;
    final newPlan = List<Entry>.from(state.plan)..[index] = entry;
    updatePlan(newPlan);
  }

  void clearPlan() {
    updatePlan(const []);
  }

  void moveEntry(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.plan.length) return;
    if (newIndex < 0 || newIndex > state.plan.length) return;
    final newPlan = List<Entry>.from(state.plan);
    final item = newPlan.removeAt(oldIndex);
    if (newIndex > newPlan.length) newIndex = newPlan.length;
    newPlan.insert(newIndex, item);
    updatePlan(newPlan);
  }

  void _saveCurrentPlan(List<Entry> plan) {
    final newSavedPlans = Map<String, dynamic>.from(state.savedPlans);
    newSavedPlans[state.activePlan] = plan.map((e) => e.toJson()).toList();
    if (_prefs != null) {
      _prefs!.setString('plans', jsonEncode(newSavedPlans));
    }
    state = state.copyWith(savedPlans: newSavedPlans);
  }
}




