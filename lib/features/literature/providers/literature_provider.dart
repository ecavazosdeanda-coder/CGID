import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_model.dart';

final literatureProvider =
    AsyncNotifierProvider<LiteratureNotifier, List<DocumentModel>>(() {
  return LiteratureNotifier();
});

class LiteratureNotifier extends AsyncNotifier<List<DocumentModel>> {
  static const _cacheKey = 'literature_cache_v1';
  static const _deletedIdsKey = 'literature_deleted_ids_v1';

  @override
  Future<List<DocumentModel>> build() async {
    return _loadLiterature();
  }

  Future<List<DocumentModel>> _loadLiterature() async {
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = (prefs.getStringList(_deletedIdsKey) ?? []).toSet();

    final Map<String, DocumentModel> docMap = {};

    // 1. Cargar documentos base del catálogo de assets
    try {
      final jsonString =
          await rootBundle.loadString('assets/data/literature_catalog.json');
      final data = jsonDecode(jsonString);
      final List<dynamic> docsJson = data['documents'] ?? [];
      for (final e in docsJson) {
        final doc = DocumentModel.fromJson(e);
        if (!deletedIds.contains(doc.id)) {
          docMap[doc.id] = doc;
        }
      }
    } catch (_) {}

    // 2. Cargar caché local de SharedPreferences (para funcionamiento offline)
    try {
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null) {
        final List<dynamic> list = jsonDecode(cachedJson);
        for (final item in list) {
          final doc = DocumentModel.fromJson(item);
          if (!deletedIds.contains(doc.id)) {
            docMap[doc.id] = doc;
          }
        }
      }
    } catch (_) {}

    // 3. Sincronizar desde Cloud Firestore
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('literature')
          .get()
          .timeout(const Duration(seconds: 4));

      for (final docSnap in snapshot.docs) {
        final data = docSnap.data();
        data['id'] = docSnap.id;
        final doc = DocumentModel.fromJson(data);
        if (!deletedIds.contains(doc.id)) {
          docMap[doc.id] = doc;
        }
      }

      // Guardar en caché local
      final serialized =
          jsonEncode(docMap.values.map((d) => d.toJson()).toList());
      await prefs.setString(_cacheKey, serialized);
    } catch (_) {
      // Si falla Firestore o no hay internet, continúa con la caché y assets locales
    }

    return docMap.values.toList();
  }

  Future<void> addOrUpdateDocument(DocumentModel doc) async {
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = (prefs.getStringList(_deletedIdsKey) ?? []).toSet();
    deletedIds.remove(doc.id);
    await prefs.setStringList(_deletedIdsKey, deletedIds.toList());

    // 1. Guardar en Firestore
    await FirebaseFirestore.instance
        .collection('literature')
        .doc(doc.id)
        .set(doc.toJson(), SetOptions(merge: true));

    // 2. Actualizar estado y caché local
    final currentList = state.value ?? [];
    final updatedList = [
      for (final d in currentList)
        if (d.id != doc.id) d,
      doc,
    ];

    state = AsyncData(updatedList);
    final serialized =
        jsonEncode(updatedList.map((d) => d.toJson()).toList());
    await prefs.setString(_cacheKey, serialized);
  }

  Future<void> deleteDocument(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = (prefs.getStringList(_deletedIdsKey) ?? []).toSet();
    deletedIds.add(docId);
    await prefs.setStringList(_deletedIdsKey, deletedIds.toList());

    // 1. Eliminar en Firestore
    try {
      await FirebaseFirestore.instance
          .collection('literature')
          .doc(docId)
          .delete();
    } catch (_) {}

    // 2. Actualizar estado y caché local
    final currentList = state.value ?? [];
    final updatedList = currentList.where((d) => d.id != docId).toList();

    state = AsyncData(updatedList);
    final serialized =
        jsonEncode(updatedList.map((d) => d.toJson()).toList());
    await prefs.setString(_cacheKey, serialized);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadLiterature());
  }
}
