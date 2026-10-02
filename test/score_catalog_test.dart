import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cgid/content.dart';
import 'package:cgid/features/hymnal/services/hymn_customization_service.dart';
import 'package:cgid/features/hymnal/services/score_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HymnCustomizationService.setAdminForTesting(true);
  });

  tearDown(() {
    HymnCustomizationService.setAdminForTesting(false);
  });

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

  test('hymns start clean and support custom chords saving and clearing', () async {
    final custom = await hymnCustomizationService.getCustomChords('h1');
    expect(custom, isNull);

    await hymnCustomizationService.saveCustomChords('h1', const [
      Section('Estrofa 1', '[G]Santo [C]Dios'),
    ]);

    final saved = await hymnCustomizationService.getCustomChords('h1');
    expect(saved, isNotNull);
    expect(saved!.first.text, '[G]Santo [C]Dios');

    await hymnCustomizationService.clearCustomChords('h1');
    final cleared = await hymnCustomizationService.getCustomChords('h1');
    expect(cleared, isNull);
  });
}
