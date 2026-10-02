import 'package:flutter_test/flutter_test.dart';

import 'package:cgid/content.dart';
import 'package:cgid/features/hymnal/services/score_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog loads digital MusicXML instead of relying on PDF pages',
    () async {
      await scoreCatalog.load();

      expect(scoreCatalog.entries.length, greaterThanOrEqualTo(300));
      expect(scoreCatalog['h1']?.files, isNotEmpty);
      expect(scoreCatalog['h1']?.assetKeyFor(0), 'assets/scores/page-002.mxl');
    },
  );

  test(
    'chords are extracted from OCR MusicXML and applied to lyrics',
    () async {
      await scoreCatalog.load();
      final chart = await scoreCatalog.chordChartFor('h1');

      expect(chart, isNotNull);
      expect(chart!.isEmpty, isFalse);
      expect(chart.keyLabel, 'G');
      final sections = chart.applyToSections(const [
        Section('Estrofa', 'Quiero cantar a mi Salvador'),
      ]);
      expect(sections.single.text, contains(RegExp(r'\[[A-G]')));
    },
  );

  test('transpose supports chord qualities, slash bass and solfeo', () {
    expect(
      ChordTransposer.transposeText('[G]Canto [D/F#]hoy', 2),
      '[A]Canto [E/G#]hoy',
    );
    expect(
      ChordTransposer.transposeText('[Am]Canto', 0, useSolfeo: true),
      '[Lam]Canto',
    );
  });
}
