import 'dart:async';
import 'dart:typed_data';

import 'package:cgid/features/literature/models/document_model.dart';
import 'package:cgid/features/literature/presentation/document_viewer_screen.dart';
import 'package:cgid/features/literature/services/literature_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingPdfService extends LiteraturePdfService {
  final result = Completer<Uint8List>();
  @override
  Future<Uint8List?> downloaded(DocumentModel doc) async => null;
  @override
  Future<Uint8List> fetch(DocumentModel doc) => result.future;
}

void main() {
  for (final fail in [false, true]) {
    testWidgets('visor permite regresar durante ${fail ? 'error' : 'carga'}', (
      tester,
    ) async {
      final service = PendingPdfService();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentViewerScreen(
                      pdfService: service,
                      document: const DocumentModel(
                        id: 'test',
                        title: 'Documento',
                        description: '',
                        category: DocumentCategory.otro,
                        author: '',
                        year: '2026',
                        url: 'https://example.org/test.pdf',
                      ),
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byType(BackButton), findsOneWidget);
      if (fail) {
        service.result.completeError(StateError('No se pudo leer el PDF'));
        await tester.pump();
        expect(find.text('Reintentar'), findsOneWidget);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!fail) {
        service.result.completeError(StateError('Finalizó después de salir'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
