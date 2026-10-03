import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cgid/content.dart';
import 'package:cgid/features/hymnal/presentation/chord_lyrics_view.dart';
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
      expect(
        scoreCatalog['h1']?.assetKeyFor(0),
        'assets/scores/auto_corrected/page-002.mxl',
      );
      expect(scoreCatalog['h1']?.originalFiles, isNotEmpty);
      expect(scoreCatalog['h1']?.requiresVerification, isTrue);
      expect(scoreCatalog['h1']?.metricIssueCount, greaterThan(0));
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

  test(
    'hymns start clean and support custom chords saving and clearing',
    () async {
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
    },
  );

  test('score verification is explicit and can be reopened', () async {
    final initial = await hymnCustomizationService.getScoreVerification('h1');
    expect(initial.verified, isFalse);

    expect(
      await hymnCustomizationService.saveScoreVerification(
        'h1',
        verified: true,
        notes: 'Comparada con el original.',
      ),
      isTrue,
    );
    final verified = await hymnCustomizationService.getScoreVerification('h1');
    expect(verified.verified, isTrue);
    expect(verified.notes, contains('original'));

    expect(
      await hymnCustomizationService.saveScoreVerification(
        'h1',
        verified: false,
      ),
      isTrue,
    );
    final reopened = await hymnCustomizationService.getScoreVerification('h1');
    expect(reopened.verified, isFalse);
  });

  test('parseTokenSlices correctly separates multiple chords within words', () {
    final slices = parseTokenSlices('per[G]d[D]ón.');
    expect(slices.length, 3);
    expect(slices[0].chord, isNull);
    expect(slices[0].text, 'per');
    expect(slices[1].chord, 'G');
    expect(slices[1].text, 'd');
    expect(slices[2].chord, 'D');
    expect(slices[2].text, 'ón.');

    final prefix = parseTokenSlices('[G]Quiero');
    expect(prefix.length, 1);
    expect(prefix[0].chord, 'G');
    expect(prefix[0].text, 'Quiero');

    final mid = parseTokenSlices('a[C]fecto');
    expect(mid.length, 2);
    expect(mid[0].chord, isNull);
    expect(mid[0].text, 'a');
    expect(mid[1].chord, 'C');
    expect(mid[1].text, 'fecto');

    final consecutive = parseTokenSlices('[G][D]');
    expect(consecutive.length, 2);
    expect(consecutive[0].chord, 'G');
    expect(consecutive[0].text, '');
    expect(consecutive[1].chord, 'D');
    expect(consecutive[1].text, '');
  });
}
