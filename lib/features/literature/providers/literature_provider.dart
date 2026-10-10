import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/providers/user_profile_provider.dart';
import '../models/document_model.dart';
import '../services/drive_document_link.dart';

// Se conservan los archivos originales; no son publicaciones del catálogo.
const bundledLiteratureIds = {
  'fe-oficial-1',
  'biblia-rvr-1909',
  'himnario-1',
  'partituras-1',
  'revista-oct26',
};
const bundledLiteraturePaths = {
  'assets/pdfs/fe.pdf',
  'assets/pdfs/biblia.pdf',
  'assets/pdfs/himnario.pdf',
  'assets/pdfs/partituras_app.pdf',
};

bool isPublishedLiterature(DocumentModel doc) =>
    !bundledLiteratureIds.contains(doc.id) &&
    !bundledLiteraturePaths.contains(doc.assetPath);

abstract class LiteratureRepository {
  Future<List<DocumentModel>> fetch();
  Stream<List<DocumentModel>> watch();
  Future<void> save(DocumentModel doc);
  Future<void> hide(String id);
}

class FirestoreLiteratureRepository implements LiteratureRepository {
  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection('literature');

  List<DocumentModel> _documents(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => [
    for (final item in snapshot.docs)
      if (item.data()['hidden'] != true)
        DocumentModel.fromJson({...item.data(), 'id': item.id}),
  ].where(isPublishedLiterature).toList();

  @override
  Future<List<DocumentModel>> fetch() async => _documents(
    await _collection
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10)),
  );

  @override
  Stream<List<DocumentModel>> watch() => _collection
      .snapshots(includeMetadataChanges: true)
      // No anunciar éxito mientras Firebase aún no autoriza la escritura local.
      .where(
        (snapshot) =>
            !snapshot.metadata.hasPendingWrites &&
            !snapshot.metadata.isFromCache,
      )
      .map(_documents);

  @override
  Future<void> save(DocumentModel doc) => _collection.doc(doc.id).set({
    ...doc.toJson(),
    'hidden': false,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  @override
  Future<void> hide(String id) => _collection.doc(id).set({
    'hidden': true,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

final literatureRepositoryProvider = Provider<LiteratureRepository>(
  (ref) => FirestoreLiteratureRepository(),
);
final literatureProvider =
    AsyncNotifierProvider<LiteratureNotifier, List<DocumentModel>>(
      LiteratureNotifier.new,
    );

String literatureErrorMessage(Object error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied' || error.code == 'unauthorized') {
      return 'Firebase rechazó los permisos. Sal de la simulación e inicia sesión como administrador; vuelve a intentar. El cambio no se confirmó.';
    }
    if ([
      'bucket-not-found',
      'no-default-bucket',
      'project-not-found',
    ].contains(error.code)) {
      return 'No hay almacenamiento de archivos configurado. Publica un enlace HTTPS al PDF o solicita configurar almacenamiento; no se activarán servicios con costo automáticamente.';
    }
    return 'No se pudo confirmar la operación en Firebase (${error.code}). Revisa la conexión y vuelve a intentar.';
  }
  if (error is TimeoutException) {
    return 'No se recibió confirmación a tiempo. La operación puede sincronizarse después; revisa el catálogo antes de repetirla.';
  }
  if (error is StateError || error is ArgumentError) return error.toString();
  return 'No se pudo completar la operación. Revisa la conexión y vuelve a intentar.';
}

class LiteratureNotifier extends AsyncNotifier<List<DocumentModel>> {
  static const cacheKey = 'literature_cache_v2';
  String? syncWarning;
  LiteratureRepository get _repository =>
      ref.read(literatureRepositoryProvider);

  @override
  Future<List<DocumentModel>> build() async {
    final documents = await _load();
    final subscription = _repository.watch().listen(
      (documents) async {
        syncWarning = null;
        state = AsyncData(documents.where(isPublishedLiterature).toList());
        await _cache(documents);
      },
      onError: (Object error) {
        syncWarning = literatureErrorMessage(error);
        state = AsyncData([...?state.value]);
      },
    );
    ref.onDispose(() => unawaited(subscription.cancel()));
    return documents;
  }

  Future<void> _cache(List<DocumentModel> documents) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode(
          documents
              .where(isPublishedLiterature)
              .map((d) => d.toJson())
              .toList(),
        ),
      );
    } catch (_) {
      syncWarning = 'Catálogo sincronizado; no se pudo actualizar la caché de este dispositivo.';
    }
  }

  Future<List<DocumentModel>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // Servidor autoritativo: vacío significa vacío, sin mezclar assets ni caché.
      final documents = (await _repository.fetch())
          .where(isPublishedLiterature)
          .toList();
      syncWarning = null;
      await _cache(documents);
      return documents;
    } catch (error) {
      syncWarning =
          'Sin sincronización confirmada. ${literatureErrorMessage(error)}';
      try {
        final cached =
            prefs.getString(cacheKey) ??
            prefs.getString('literature_cache_v1') ??
            '[]';
        final removed = (prefs.getStringList('literature_deleted_ids_v1') ?? [])
            .toSet();
        return (jsonDecode(cached) as List)
            .map(
              (item) => DocumentModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .where(
              (doc) => isPublishedLiterature(doc) && !removed.contains(doc.id),
            )
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> _requireAdmin() async {
    final profile = await ref.read(userProfileProvider.future);
    if (profile?.isAdmin != true) {
      throw StateError(
        'Solo un administrador puede publicar o quitar literatura. Sal del modo de simulación.',
      );
    }
  }

  Future<void> addOrUpdateDocument(DocumentModel doc) async {
    await _requireAdmin();
    if (doc.id.isEmpty || doc.id.length > 100 || doc.id.contains('/')) {
      throw ArgumentError('Identificador de documento inválido.');
    }
    if (!isPublishedLiterature(doc)) {
      throw ArgumentError(
        'Los originales locales están ocultos del catálogo por el momento.',
      );
    }
    final publication = doc.copyWith(
      url: normalizeLiteratureUrl(doc.url ?? ''),
    );
    await _repository.save(publication).timeout(const Duration(seconds: 20));
    final updated = [
      for (final current in state.value ?? <DocumentModel>[])
        if (current.id != doc.id) current,
      publication,
    ];
    state = AsyncData(updated);
    await _cache(updated);
  }

  Future<void> deleteDocument(String id) async {
    await _requireAdmin();
    if (id.isEmpty || id.length > 100 || id.contains('/')) {
      throw ArgumentError('Identificador de documento inválido.');
    }
    // Borrado lógico global: conservar archivos y metadatos recuperables.
    await _repository.hide(id).timeout(const Duration(seconds: 20));
    final updated = (state.value ?? <DocumentModel>[])
        .where((doc) => doc.id != id)
        .toList();
    state = AsyncData(updated);
    await _cache(updated);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }
}
