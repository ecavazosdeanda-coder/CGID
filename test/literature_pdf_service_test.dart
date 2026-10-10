import 'dart:typed_data';

import 'package:cgid/features/literature/models/document_model.dart';
import 'package:cgid/features/literature/services/drive_document_link.dart';
import 'package:cgid/features/literature/services/literature_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const pdfDocument = DocumentModel(
  id: 'test-pdf',
  title: 'PDF',
  description: '',
  category: DocumentCategory.otro,
  author: '',
  year: '2026',
  url: 'https://drive.google.com/file/d/1234567890abcdef/view?resourcekey=0-test',
);
final pdfBytes = Uint8List.fromList('%PDF-1.7\ncontenido'.codeUnits);

class MemoryPdfCache implements LiteraturePdfCache {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    values[key] = bytes;
  }
}

void main() {
  test('normaliza variantes de enlace y conserva resource key', () {
    final link = DriveDocumentLink.tryParse(pdfDocument.url!)!;
    expect(link.fileId, '1234567890abcdef');
    expect(link.resourceKey, '0-test');
    expect(
      normalizeLiteratureUrl(
        'https://drive.google.com/open?id=1234567890abcdef',
      ),
      'https://drive.google.com/file/d/1234567890abcdef/view',
    );
    expect(
      normalizeLiteratureUrl(
        'https://drive.google.com/uc?id=1234567890abcdef&export=download',
      ),
      'https://drive.google.com/file/d/1234567890abcdef/view',
    );
  });
  test('rechaza carpetas, Docs, credenciales y protocolos no seguros', () {
    for (final source in [
      'https://drive.google.com/drive/folders/1234567890abcdef',
      'https://docs.google.com/document/d/1234567890abcdef/edit',
      'https://user:password@drive.google.com/file/d/1234567890abcdef/view',
      'http://drive.google.com/open?id=1234567890abcdef',
    ]) {
      expect(() => normalizeLiteratureUrl(source), throwsArgumentError);
    }
  });
  test(
    'Drive usa bytes de API y resource key, nunca vista web ni exportación',
    () async {
      final service = LiteraturePdfService(
        cache: MemoryPdfCache(),
        driveApiKey: 'test-public-key',
        transport: MockClient((request) async {
          expect(request.url.host, 'www.googleapis.com');
          expect(request.url.path, '/drive/v3/files/1234567890abcdef');
          expect(request.url.queryParameters['alt'], 'media');
          expect(
            request.headers['X-Goog-Drive-Resource-Keys'],
            '1234567890abcdef/0-test',
          );
          return http.Response.bytes(pdfBytes, 200);
        }),
      );
      expect(await service.fetch(pdfDocument), pdfBytes);
      expect(
        await service.downloaded(pdfDocument),
        isNull,
        reason: 'ver online no equivale a guardar offline',
      );
    },
  );
  test(
    'copia descargada persiste y se puede leer sin pedir internet',
    () async {
      final cache = MemoryPdfCache();
      final online = LiteraturePdfService(cache: cache);
      await online.saveOffline(pdfDocument, pdfBytes);
      var requests = 0;
      final reopened = LiteraturePdfService(
        cache: cache,
        transport: MockClient((_) async {
          requests++;
          throw http.ClientException('offline');
        }),
      );
      final bytes =
          await reopened.downloaded(pdfDocument) ??
          await reopened.fetch(pdfDocument);
      expect(bytes, pdfBytes);
      expect(requests, 0);
    },
  );
  test('cambiar enlace no reutiliza una copia de otra versión', () async {
    final service = LiteraturePdfService(cache: MemoryPdfCache());
    await service.saveOffline(pdfDocument, pdfBytes);
    expect(
      await service.downloaded(
        pdfDocument.copyWith(
          url: 'https://drive.google.com/file/d/abcdef1234567890/view',
        ),
      ),
      isNull,
    );
    expect(
      await service.downloaded(pdfDocument),
      pdfBytes,
      reason: 'los archivos locales se conservan',
    );
  });
  test('clave faltante no abre Drive ni intenta Firebase Storage', () async {
    final service = LiteraturePdfService(
      cache: MemoryPdfCache(),
      driveApiKey: '',
    );
    await expectLater(service.fetch(pdfDocument), throwsStateError);
  });
  test('rechaza HTML de login y archivos no PDF', () async {
    final service = LiteraturePdfService(
      cache: MemoryPdfCache(),
      transport: MockClient(
        (_) async => http.Response('<html>login</html>', 200),
      ),
    );
    await expectLater(service.fetch(pdfDocument), throwsArgumentError);
    expect(await service.downloaded(pdfDocument), isNull);
  });
  test(
    'permisos, archivo inexistente y cuota no generan descargas falsas',
    () async {
      for (final status in [403, 404, 429]) {
        final service = LiteraturePdfService(
          cache: MemoryPdfCache(),
          transport: MockClient((_) async => http.Response('error', status)),
        );
        await expectLater(service.fetch(pdfDocument), throwsStateError);
        expect(await service.downloaded(pdfDocument), isNull);
      }
    },
  );
  test(
    'límite de tamaño se aplica al stream incluso sin Content-Length',
    () async {
      final service = LiteraturePdfService(
        cache: MemoryPdfCache(),
        transport: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(Uint8List(maxLiteraturePdfBytes + 1)),
            200,
          ),
        ),
      );
      await expectLater(service.fetch(pdfDocument), throwsArgumentError);
    },
  );
}
