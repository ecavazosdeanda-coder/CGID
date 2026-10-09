import 'package:flutter_test/flutter_test.dart';

import 'package:cgid/features/ai_assistant/services/doctrinal_corpus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DoctrinalCorpus corpus;

  setUpAll(() async {
    corpus = DoctrinalCorpus();
    await corpus.load();
  });

  test('loads the complete authorized corpus', () {
    expect(corpus.stats.faithDocuments, 40);
    expect(corpus.stats.bibleDocuments, greaterThan(5000));
  });

  test('retrieves the Sabbath point of faith with a citable source', () {
    final results = corpus.search(
      '¿Qué enseñan los Puntos de Fe acerca del reposo del sábado?',
    );

    expect(results, isNotEmpty);
    expect(
      results.any(
        (source) =>
            source.type == DoctrinalSourceType.faith &&
            source.reference.contains('27'),
      ),
      isTrue,
    );
  });

  test('retrieves a direct Bible reference', () {
    final results = corpus.search('Juan 3:16');

    expect(results, isNotEmpty);
    expect(
      results.any(
        (source) =>
            source.type == DoctrinalSourceType.bible &&
            source.reference.contains('Juan 3:'),
      ),
      isTrue,
    );
  });

  test('does not fabricate sources for an unrelated technical question', () {
    final results = corpus.search(
      '¿Cómo programo una aplicación bancaria en Flutter?',
    );

    expect(results, isEmpty);
  });
}
