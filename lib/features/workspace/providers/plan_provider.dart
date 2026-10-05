import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../../content.dart';

class PlanState {
  final List<Entry> plan;
  final String activePlan;
  final Map<String, dynamic> savedPlans;
  final Map<String, dynamic> planMetadata;
  final bool isSyncing;
  final String? churchId;

  const PlanState({
    required this.plan,
    required this.activePlan,
    required this.savedPlans,
    required this.planMetadata,
    this.isSyncing = false,
    this.churchId,
  });

  PlanState copyWith({
    List<Entry>? plan,
    String? activePlan,
    Map<String, dynamic>? savedPlans,
    Map<String, dynamic>? planMetadata,
    bool? isSyncing,
    String? churchId,
  }) {
    return PlanState(
      plan: plan ?? this.plan,
      activePlan: activePlan ?? this.activePlan,
      savedPlans: savedPlans ?? this.savedPlans,
      planMetadata: planMetadata ?? this.planMetadata,
      isSyncing: isSyncing ?? this.isSyncing,
      churchId: churchId ?? this.churchId,
    );
  }
}

final planProvider = NotifierProvider<PlanNotifier, PlanState>(
  () => PlanNotifier(),
);

class PlanNotifier extends Notifier<PlanState> {
  SharedPreferences? _prefs;
  StreamSubscription? _plansSub;
  StreamSubscription? _privateNotesSub;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  PlanState build() {
    return const PlanState(
      plan: [],
      activePlan: '',
      savedPlans: {},
      planMetadata: {},
    );
  }

  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    final activePlan = _prefs!.getString('activePlan') ?? '';
    
    // Fallback inicial offline desde _prefs
    Map<String, dynamic> initialSavedPlans = {};
    Map<String, dynamic> initialMetadata = {};
    
    try {
      final savedPlansStr = _prefs!.getString('plans');
      if (savedPlansStr != null) {
        initialSavedPlans = jsonDecode(savedPlansStr);
      }
      final metadataStr = _prefs!.getString('planMetadata');
      if (metadataStr != null) {
        initialMetadata = jsonDecode(metadataStr);
      }
    } catch (_) {}

    final initialPlanRaw = initialSavedPlans[activePlan] as List? ?? [];
    final initialPlan = initialPlanRaw.map((e) => Entry.fromJson(Map<String, dynamic>.from(e))).toList();

    state = state.copyWith(
      activePlan: activePlan,
      savedPlans: initialSavedPlans,
      planMetadata: initialMetadata,
      plan: initialPlan,
    );
  }

  // --- Real-time Sync ---

  void listenToChurch(String churchId) {
    if (churchId.isEmpty) return;
    if (state.churchId == churchId) return;

    _plansSub?.cancel();
    _privateNotesSub?.cancel();

    state = state.copyWith(churchId: churchId, isSyncing: true);

    // 1. Escuchar los planes públicos
    _plansSub = _db
        .collection('churches')
        .doc(churchId)
        .collection('plans')
        .snapshots()
        .listen((snapshot) {
      _processSnapshots(churchId, snapshot.docs);
    }, onError: (e) {
      debugPrint('Error en planes públicos: $e');
    });

    // 2. Escuchar las notas privadas
    _privateNotesSub = _db
        .collection('churches')
        .doc(churchId)
        .collection('private_plans')
        .snapshots()
        .listen((snapshot) {
      // Las combinamos usando Firestore persistentLocalCache de forma transparente
      // Ya que este listener forzará actualización de UI
      _db.collection('churches').doc(churchId).collection('plans').get(const GetOptions(source: Source.cache)).then((cachedPlans) {
         _processSnapshots(churchId, cachedPlans.docs);
      });
    }, onError: (e) {
      debugPrint('Error en notas privadas (puede ser normal si no hay permisos): $e');
    });
  }

  Future<void> _processSnapshots(String churchId, List<QueryDocumentSnapshot> planDocs) async {
    final Map<String, dynamic> newSavedPlans = {};
    final Map<String, dynamic> newMetadata = {};

    // Buscar si existe el formato viejo (weekly_plans) para mantener lectura
    final legacyDoc = planDocs.cast<QueryDocumentSnapshot?>().firstWhere(
      (doc) => doc?.id == 'weekly_plans',
      orElse: () => null,
    );

    if (legacyDoc != null && legacyDoc.exists) {
      final data = legacyDoc.data() as Map<String, dynamic>;
      final legacyPlans = Map<String, dynamic>.from(data['plans'] ?? {});
      final legacyMeta = Map<String, dynamic>.from(data['planMetadata'] ?? {});
      
      newSavedPlans.addAll(legacyPlans);
      newMetadata.addAll(legacyMeta);
      
      // Intentar leer notas legadas
      try {
        final legacyPrivate = await _db.collection('churches').doc(churchId).collection('private_plans').doc('weekly_plans').get(const GetOptions(source: Source.cache));
        if (legacyPrivate.exists) {
           final legacyNotes = Map<String, dynamic>.from(legacyPrivate.data()?['notes'] ?? {});
           for (final entry in legacyNotes.entries) {
              final pName = entry.key;
              final pNotesList = entry.value as List? ?? [];
              final targetPlan = newSavedPlans[pName] as List?;
              if (targetPlan != null) {
                for (int i=0; i < pNotesList.length && i < targetPlan.length; i++) {
                   targetPlan[i]['notes'] = pNotesList[i] ?? '';
                }
              }
           }
        }
      } catch (_) {}
    }

    // Leer el formato nuevo
    final newFormatDocs = planDocs.where((d) => d.id != 'weekly_plans').toList();
    
    for (final doc in newFormatDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final title = data['title'] as String? ?? doc.id;
      final entries = data['entries'] as List? ?? [];
      final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
      metadata['revision'] = data['revision'] as int? ?? 0;
      
      // Transformar para el formato actual
      newSavedPlans[title] = List.from(entries);
      newMetadata[title] = metadata;

      // Unir con notas privadas del formato nuevo
      try {
        final privDoc = await _db.collection('churches').doc(churchId).collection('private_plans').doc(doc.id).get(const GetOptions(source: Source.cache));
        if (privDoc.exists) {
          final notesMap = privDoc.data()?['notes'] as Map<String, dynamic>? ?? {};
          final targetPlan = newSavedPlans[title] as List;
          for (int i = 0; i < targetPlan.length; i++) {
             final entryData = targetPlan[i] as Map<String, dynamic>;
             final eId = entryData['id'];
             if (notesMap.containsKey(eId)) {
                entryData['notes'] = notesMap[eId];
             }
          }
        }
      } catch (_) {}
    }

    _prefs?.setString('plans', jsonEncode(newSavedPlans));
    _prefs?.setString('planMetadata', jsonEncode(newMetadata));

    List<Entry> currentPlan = [];
    if (newSavedPlans.containsKey(state.activePlan)) {
      currentPlan = (newSavedPlans[state.activePlan] as List)
          .map((e) => Entry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    state = state.copyWith(
      savedPlans: newSavedPlans,
      planMetadata: newMetadata,
      plan: currentPlan,
      isSyncing: false,
    );
  }

  // Compatibilidad hacia atrás de la API
  Future<void> fetchFromCloud(String churchId) async {
    listenToChurch(churchId);
  }

  Future<void> syncToCloud(String churchId) async {
    final active = state.activePlan;
    if (active.isEmpty) return;
    
    state = state.copyWith(isSyncing: true);
    
    try {
       // Save using the new format document (transactional)
       final planId = active.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
       final planRef = _db.collection('churches').doc(churchId).collection('plans').doc(planId);
       final privRef = _db.collection('churches').doc(churchId).collection('private_plans').doc(planId);
       
       final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

       await _db.runTransaction((tx) async {
          final snap = await tx.get(planRef);
          int newRevision = 1;
          if (snap.exists) {
            final remoteRevision = snap.data()?['revision'] as int? ?? 0;
            final localMetadataRaw = state.planMetadata[active];
            final localRevision = localMetadataRaw is Map ? (localMetadataRaw['revision'] as int? ?? 0) : 0;
            if (remoteRevision > localRevision) {
              throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted', message: 'CONFLICTO: El culto ha sido modificado en la nube por otro usuario. Descarga los cambios antes de volver a guardar.');
            }
            newRevision = remoteRevision + 1;
          }

          final rawEntries = state.savedPlans[active] as List? ?? [];
          final publicEntries = [];
          final Map<String, String> privateNotes = {};

          for (final raw in rawEntries) {
            final e = Map<String, dynamic>.from(raw as Map);
            final note = e['notes'] as String? ?? '';
            final eId = e['id'] as String;
            e['notes'] = ''; // clear for public
            publicEntries.add(e);
            
            if (note.trim().isNotEmpty) {
               privateNotes[eId] = note;
            }
          }

          final publicData = {
            'title': active,
            'entries': publicEntries,
            'metadata': state.planMetadata[active] ?? {},
            'revision': newRevision,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          };

          final privateData = {
            'notes': privateNotes,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
            'revision': newRevision,
          };

          tx.set(planRef, publicData);
          tx.set(privRef, privateData);
       });
       debugPrint('Sincronizado a la nube con éxito.');
    } catch (e) {
      debugPrint('Error sincronizando plan: $e');
      rethrow;
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> deletePlan(String churchId, String planName) async {
    final planId = planName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final planRef = _db.collection('churches').doc(churchId).collection('plans').doc(planId);
    final privRef = _db.collection('churches').doc(churchId).collection('private_plans').doc(planId);

    await _db.runTransaction((tx) async {
      tx.delete(planRef);
      tx.delete(privRef);
    });

    final newSavedPlans = Map<String, dynamic>.from(state.savedPlans)..remove(planName);
    final newMetadata = Map<String, dynamic>.from(state.planMetadata)..remove(planName);
    
    _prefs?.setString('plans', jsonEncode(newSavedPlans));
    _prefs?.setString('planMetadata', jsonEncode(newMetadata));

    state = state.copyWith(
      savedPlans: newSavedPlans,
      planMetadata: newMetadata,
      activePlan: state.activePlan == planName ? '' : state.activePlan,
      plan: state.activePlan == planName ? [] : state.plan,
    );
  }

  // --- Mismos métodos locales de antes ---

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
}
