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
  final Map<String, dynamic> planMetadata;
  final bool isSyncing;

  const PlanState({
    required this.plan,
    required this.activePlan,
    required this.savedPlans,
    required this.planMetadata,
    this.isSyncing = false,
  });

  PlanState copyWith({
    List<Entry>? plan,
    String? activePlan,
    Map<String, dynamic>? savedPlans,
    Map<String, dynamic>? planMetadata,
    bool? isSyncing,
  }) {
    return PlanState(
      plan: plan ?? this.plan,
      activePlan: activePlan ?? this.activePlan,
      savedPlans: savedPlans ?? this.savedPlans,
      planMetadata: planMetadata ?? this.planMetadata,
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
      planMetadata: {},
    );
  }

  void init(SharedPreferences prefs) {
    _prefs = prefs;
    Map<String, dynamic> savedPlans = {};
    Map<String, dynamic> planMetadata = {};
    String activePlan = 'Culto del sábado';
    List<Entry> plan = [];

    try {
      savedPlans = jsonDecode(prefs.getString('plans') ?? '{}');
      planMetadata = jsonDecode(prefs.getString('planMetadata') ?? '{}');
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
      planMetadata: planMetadata,
    );
  }

  Future<void> syncToCloud(String churchId, {bool forceOverwrite = false}) async {
    if (churchId.isEmpty) return;
    state = state.copyWith(isSyncing: true);
    try {
      final db = FirebaseFirestore.instance;
      final publicRef = db
          .collection('churches')
          .doc(churchId)
          .collection('plans')
          .doc('weekly_plans');
      final privateRef = db
          .collection('churches')
          .doc(churchId)
          .collection('private_plans')
          .doc('weekly_plans');

      final lastSyncTimeRaw = _prefs?.getString('lastSyncTime_$churchId');

      await db.runTransaction((transaction) async {
        final publicDoc = await transaction.get(publicRef);

        if (!forceOverwrite && publicDoc.exists && publicDoc.data()!.containsKey('updatedAt')) {
          final cloudUpdatedAt = publicDoc.data()!['updatedAt'] as Timestamp?;
          if (cloudUpdatedAt != null && lastSyncTimeRaw != null) {
            final localLastSync = DateTime.tryParse(lastSyncTimeRaw);
            // Tolerancia de 2 segundos para evitar falsos positivos
            if (localLastSync != null && cloudUpdatedAt.toDate().difference(localLastSync).inSeconds > 2) {
              throw Exception('CONFLICT: Hay cambios más recientes en la nube. Por favor, descarga la última versión primero para evitar sobrescribir el trabajo de otro.');
            }
          }
        }

        transaction.set(publicRef, {
          'plans': publicPlansForCloud(state.savedPlans),
          'planMetadata': state.planMetadata,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(privateRef, {
          'notes': privateNotesForCloud(state.savedPlans),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
          'Tiempo de espera agotado. Verifica tu conexión a internet.',
        ),
      );

      _prefs?.setString('lastSyncTime_$churchId', DateTime.now().toUtc().toIso8601String());
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
        final cloudMetadata = Map<String, dynamic>.from(
          data['planMetadata'] ?? {},
        );
        Map<String, dynamic> privateNotes = {};
        var preserveLegacyLocalNotes = false;
        try {
          final privateDoc = await db
              .collection('churches')
              .doc(churchId)
              .collection('private_plans')
              .doc('weekly_plans')
              .get();
          preserveLegacyLocalNotes = !privateDoc.exists;
          privateNotes = Map<String, dynamic>.from(
            privateDoc.data()?['notes'] ?? {},
          );
        } catch (_) {
          // Las pantallas públicas pueden descargar el orden, pero nunca las
          // notas ministeriales. Ante permisos insuficientes se limpian.
        }
        final mergedPlans = _mergePrivateNotes(
          cloudPlans,
          privateNotes,
          state.savedPlans,
          preserveLegacyLocalNotes: preserveLegacyLocalNotes,
        );
        _prefs?.setString('plans', jsonEncode(mergedPlans));
        _prefs?.setString('planMetadata', jsonEncode(cloudMetadata));

        final newPlan = [
          for (final e in mergedPlans[state.activePlan] ?? [])
            Entry.fromJson(Map<String, dynamic>.from(e)),
        ];

        final cloudUpdatedAt = data['updatedAt'] as Timestamp?;
        if (cloudUpdatedAt != null) {
          _prefs?.setString('lastSyncTime_$churchId', cloudUpdatedAt.toDate().toUtc().toIso8601String());
        }

        state = state.copyWith(
          savedPlans: mergedPlans,
          planMetadata: cloudMetadata,
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

  ServicePlanMetadata metadataFor(String planName) {
    final raw = state.planMetadata[planName];
    if (raw is! Map) return const ServicePlanMetadata();
    return ServicePlanMetadata.fromJson(Map<String, dynamic>.from(raw));
  }

  void updateMetadata(String planName, ServicePlanMetadata metadata) {
    final updated = Map<String, dynamic>.from(state.planMetadata)
      ..[planName] = metadata.toJson();
    _prefs?.setString('planMetadata', jsonEncode(updated));
    state = state.copyWith(planMetadata: updated);
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

  @visibleForTesting
  Map<String, dynamic> publicPlansForCloud(Map<String, dynamic> plans) => {
    for (final plan in plans.entries)
      plan.key: [
        for (final raw in plan.value as List? ?? const [])
          Map<String, dynamic>.from(raw as Map)..['notes'] = '',
      ],
  };

  @visibleForTesting
  Map<String, dynamic> privateNotesForCloud(Map<String, dynamic> plans) => {
    for (final plan in plans.entries)
      plan.key: [
        for (final raw in plan.value as List? ?? const [])
          (raw as Map)['notes'] as String? ?? '',
      ],
  };

  Map<String, dynamic> _mergePrivateNotes(
    Map<String, dynamic> publicPlans,
    Map<String, dynamic> privateNotes,
    Map<String, dynamic> localPlans, {
    bool preserveLegacyLocalNotes = false,
  }) {
    return {
      for (final plan in publicPlans.entries)
        plan.key: [
          for (
            var index = 0;
            index < (plan.value as List? ?? const []).length;
            index++
          )
            _entryWithPrivateNote(
              Map<String, dynamic>.from((plan.value as List)[index] as Map),
              index < (privateNotes[plan.key] as List? ?? const []).length
                  ? (privateNotes[plan.key] as List)[index] as String? ?? ''
                  : preserveLegacyLocalNotes &&
                        index <
                            (localPlans[plan.key] as List? ?? const []).length
                  ? ((localPlans[plan.key] as List)[index] as Map)['notes']
                            as String? ??
                        ''
                  : '',
            ),
        ],
    };
  }

  Map<String, dynamic> _entryWithPrivateNote(
    Map<String, dynamic> entry,
    String note,
  ) => entry..['notes'] = note;
}
