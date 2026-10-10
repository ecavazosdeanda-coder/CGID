
import 'package:cgid/features/literature/models/document_model.dart';
import 'package:cgid/features/literature/services/literature_pdf_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class ForbiddenCache implements LiteraturePdfCache {
  @override
  Future<Uint8List?> read(String key) async =>
      throw StateError('Web must not read previous offline copies');
  @override
  Future<void> write(String key, Uint8List bytes) async =>
      throw StateError('Web must not persist PDFs');
}

void main() {
  test(
    'web disables PDF persistence and ignores previous downloaded copies',
    () async {
      const doc = DocumentModel(
        id: 'test',
        title: 'Test',
        description: '',
        category: DocumentCategory.otro,
        author: '',
        year: '2026',
        url: 'https://example.org/test.pdf',
      );
      final service = LiteraturePdfService(cache: ForbiddenCache());
      expect(await service.downloaded(doc), isNull);
      await expectLater(
        service.saveOffline(doc, Uint8List.fromList('%PDF-1.7'.codeUnits)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            contains('aplicación instalada'),
          ),
        ),
      );
    },
    skip: !kIsWeb,
  );
}
