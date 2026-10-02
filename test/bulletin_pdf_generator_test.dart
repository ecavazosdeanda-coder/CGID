import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/content.dart';
import 'package:cgid/features/bulletin/utils/bulletin_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bulletin identifies the church and excludes private notes', () async {
    const privateNote = 'SECRETO_PASTORAL_NO_PUBLICAR';
    const churchName = 'Iglesia de Dios en Prueba';
    const entry = Entry(
      id: 'service-test',
      title: 'Predicación',
      subtitle: 'Orden de culto',
      sections: [Section('Tema', 'La esperanza cristiana')],
      notes: privateNote,
      assignments: [
        ServiceAssignment(role: 'predicador', displayName: 'Hermano de Prueba'),
      ],
    );

    final bytes = await BulletinPdfGenerator.generateBulletin(
      'Culto de prueba',
      [entry],
      churchName: churchName,
      compress: false,
    );
    final publicData = BulletinPdfGenerator.publicEntryData(entry);
    final rawPdf = latin1.decode(bytes, allowInvalid: true);

    expect(bytes, isNotEmpty);
    expect(publicData['title'], 'Predicación');
    expect(publicData['responsible'], 'Predicador: Hermano de Prueba');
    expect(publicData.values, isNot(contains(privateNote)));
    expect(rawPdf, isNot(contains(privateNote)));
  });
}
