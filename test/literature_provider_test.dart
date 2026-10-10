import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cgid/features/admin/models/user_profile_model.dart';
import 'package:cgid/features/admin/providers/user_profile_provider.dart';
import 'package:cgid/features/literature/models/document_model.dart';
import 'package:cgid/features/literature/providers/literature_provider.dart';
import 'package:cgid/features/literature/services/literature_pdf_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const admin = UserProfile(
  uid: 'admin',
  email: 'admin@example.org',
  role: 'admin',
);
const publication = DocumentModel(
  id: 'publication',
  title: 'Publicación',
  description: 'Estudio',
  category: DocumentCategory.estudiosDoctrinales,
  author: 'CGID',
  year: '2026',
  url: 'https://example.org/study.pdf',
);

class TestLiteratureRepository implements LiteratureRepository {
  TestLiteratureRepository([List<DocumentModel> documents = const []])
    : records = {for (final doc in documents) doc.id: doc};
  final Map<String, DocumentModel> records;
  final Set<String> hidden = {};
  final changes = StreamController<List<DocumentModel>>.broadcast();
  Object? fetchError;
  Object? saveError;
  Object? hideError;
  int writes = 0;
  List<DocumentModel> get visible =>
      records.values.where((doc) => !hidden.contains(doc.id)).toList();
  @override
  Future<List<DocumentModel>> fetch() async {
    if (fetchError != null) throw fetchError!;
    return visible;
  }

  @override
  Stream<List<DocumentModel>> watch() => changes.stream;
  @override
  Future<void> save(DocumentModel doc) async {
    if (saveError != null) throw saveError!;
    writes++;
    records[doc.id] = doc;
    hidden.remove(doc.id);
    changes.add(visible);
  }

  @override
  Future<void> hide(String id) async {
    if (hideError != null) throw hideError!;
    writes++;
    hidden.add(id);
    changes.add(visible);
  }
}

Future<ProviderContainer> device(
  TestLiteratureRepository repository, {
  UserProfile? profile = admin,
}) async {
  final container = ProviderContainer(
    overrides: [
      literatureRepositoryProvider.overrideWithValue(repository),
      userProfileProvider.overrideWith((ref) => Stream.value(profile)),
    ],
  );
  addTearDown(container.dispose);
  container.listen(userProfileProvider, (_, _) {});
  container.listen(literatureProvider, (_, _) {});
  await container.read(userProfileProvider.future);
  await container.read(literatureProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'servidor vacío no repone originales ni documentos obsoletos de caché',
    () async {
      SharedPreferences.setMockInitialValues({
        'literature_cache_v1': jsonEncode([
          publication.toJson(),
          publication
              .copyWith(id: 'fe-oficial-1', assetPath: 'assets/pdfs/fe.pdf')
              .toJson(),
        ]),
      });
      final repository = TestLiteratureRepository();
      addTearDown(repository.changes.close);
      final container = await device(repository);
      expect(container.read(literatureProvider).value, isEmpty);
      expect(
        jsonDecode(
          (await SharedPreferences.getInstance()).getString(
            LiteratureNotifier.cacheKey,
          )!,
        ),
        isEmpty,
      );
    },
  );

  test('offline conserva publicaciones pero oculta originales incluso con id cambiado', () async {
    SharedPreferences.setMockInitialValues({
      'literature_cache_v1': jsonEncode([
        publication.toJson(),
        publication.copyWith(id: 'fe-oficial-1').toJson(),
        publication
            .copyWith(id: 'custom-bible', assetPath: 'assets/pdfs/biblia.pdf')
            .toJson(),
      ]),
    });
    final repository = TestLiteratureRepository()
      ..fetchError = TimeoutException('offline');
    addTearDown(repository.changes.close);
    final container = await device(repository);
    expect(container.read(literatureProvider).value!.map((doc) => doc.id), [
      'publication',
    ]);
    expect(
      container.read(literatureProvider.notifier).syncWarning,
      contains('Sin sincronización'),
    );
  });

  test('ocultar se replica en otro dispositivo y conserva metadatos y URL del archivo', () async {
    final repository = TestLiteratureRepository([publication]);
    addTearDown(repository.changes.close);
    final first = await device(repository);
    final second = await device(repository);
    await first
        .read(literatureProvider.notifier)
        .deleteDocument(publication.id);
    await second.pump();
    expect(first.read(literatureProvider).value, isEmpty);
    expect(second.read(literatureProvider).value, isEmpty);
    expect(repository.records[publication.id]?.url, publication.url);
    expect(repository.hidden, contains(publication.id));
  });

  test(
    'permisos rechazados al ocultar no se silencian ni alteran estado/cache',
    () async {
      final repository = TestLiteratureRepository([publication])
        ..hideError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      addTearDown(repository.changes.close);
      final container = await device(repository);
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getString(LiteratureNotifier.cacheKey);
      await expectLater(
        container
            .read(literatureProvider.notifier)
            .deleteDocument(publication.id),
        throwsA(isA<FirebaseException>()),
      );
      expect(container.read(literatureProvider).value, [publication]);
      expect(prefs.getString(LiteratureNotifier.cacheKey), previous);
      expect(repository.hidden, isEmpty);
      expect(
        literatureErrorMessage(repository.hideError!),
        contains('Firebase rechazó los permisos'),
      );
    },
  );

  test(
    'fallo al publicar no anuncia éxito ni modifica catálogo/cache',
    () async {
      final repository = TestLiteratureRepository()
        ..saveError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      addTearDown(repository.changes.close);
      final container = await device(repository);
      await expectLater(
        container
            .read(literatureProvider.notifier)
            .addOrUpdateDocument(publication),
        throwsA(isA<FirebaseException>()),
      );
      expect(container.read(literatureProvider).value, isEmpty);
      expect(repository.records, isEmpty);
    },
  );

  test(
    'otros roles y sesiones sin cuenta no pueden publicar ni ocultar',
    () async {
      final repository = TestLiteratureRepository([publication]);
      addTearDown(repository.changes.close);
      for (final profile in [
        null,
        admin.copyWith(role: 'musico'),
        admin.copyWith(role: 'pastor'),
      ]) {
        final container = await device(repository, profile: profile);
        await expectLater(
          container
              .read(literatureProvider.notifier)
              .deleteDocument(publication.id),
          throwsStateError,
        );
        await expectLater(
          container
              .read(literatureProvider.notifier)
              .addOrUpdateDocument(publication),
          throwsStateError,
        );
      }
      expect(repository.writes, 0);
    },
  );

  test('publicación valida HTTPS e id antes de escribir en Firebase', () async {
    final repository = TestLiteratureRepository();
    addTearDown(repository.changes.close);
    final container = await device(repository);
    for (final doc in [
      publication.copyWith(url: 'javascript:alert(1)'),
      publication.copyWith(url: 'http://example.org/file.pdf'),
      publication.copyWith(id: 'a' * 101),
      publication.copyWith(id: 'fe-oficial-1'),
    ]) {
      await expectLater(
        container.read(literatureProvider.notifier).addOrUpdateDocument(doc),
        throwsArgumentError,
      );
    }
    expect(repository.writes, 0);
    await container
        .read(literatureProvider.notifier)
        .addOrUpdateDocument(publication);
    expect(repository.writes, 1);
  });

  test('snapshots reemplazan el catálogo: eliminación remota no reaparece al refrescar', () async {
    final repository = TestLiteratureRepository([publication]);
    addTearDown(repository.changes.close);
    final container = await device(repository);
    repository.records.clear();
    repository.changes.add([]);
    await container.pump();
    expect(container.read(literatureProvider).value, isEmpty);
    await container.read(literatureProvider.notifier).refresh();
    expect(container.read(literatureProvider).value, isEmpty);
  });

  test('valida contenido y tamaño real del PDF', () {
    validateLiteraturePdf(Uint8List.fromList('%PDF-1.7'.codeUnits));
    expect(
      () => validateLiteraturePdf(Uint8List.fromList('not a PDF'.codeUnits)),
      throwsArgumentError,
    );
    expect(() => validateLiteraturePdf(Uint8List(0)), throwsArgumentError);
    expect(
      () => validateLiteraturePdf(Uint8List(maxLiteraturePdfBytes + 1)),
      throwsArgumentError,
    );
  });
}
