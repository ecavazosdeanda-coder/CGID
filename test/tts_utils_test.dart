import 'package:test/test.dart';
import 'package:cgid/tts_utils.dart';

void main() {
  test('single verse conversion', () {
    final input = 'Apocalipsis 10:10';
    final expected = 'Apocalipsis capítulo 10 versículo 10';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('verse range conversion', () {
    final input = 'Apocalipsis 10:10-15';
    final expected = 'Apocalipsis capítulo 10 versículos 10 al 15';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('numbered books converted to spoken words (Primera de, Segunda de, Tercera de)', () {
    final input = '1 Pedro 2:9 y 2 Corintios 5:17 y 3 Juan 1:2';
    final expected =
        'Primera de Pedro capítulo 2 versículo 9 y Segunda de Corintios capítulo 5 versículo 17 y Tercera de Juan capítulo 1 versículo 2';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('numbered books with ranges and verses', () {
    final input = '1 Corintios 15:51-54 y 2 Timoteo 4:1';
    final expected =
        'Primera de Corintios capítulo 15 versículos 51 al 54 y Segunda de Timoteo capítulo 4 versículo 1';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('comma-separated verses', () {
    final input = 'Hechos 2:29,34';
    final expected = 'Hechos capítulo 2 versículos 29 y 34';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('multiple citations in text', () {
    final input = 'En Juan 3:16 y Apocalipsis 10:10-12 se menciona...';
    final expected =
        'En Juan capítulo 3 versículo 16 y Apocalipsis capítulo 10 versículos 10 al 12 se menciona...';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('semicolon references inherit the preceding biblical book', () {
    final input = 'Génesis 1:26; 3:22; 11:7.';
    final expected =
        'Génesis capítulo 1 versículo 26; capítulo 3 versículo 22; capítulo 11 versículo 7.';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('semicolon reference supports a verse range', () {
    final input = 'Mateo 24:1-41; 25:1-13';
    final expected =
        'Mateo capítulo 24 versículos 1 al 41; capítulo 25 versículos 1 al 13';
    expect(preprocessBiblicalCitations(input), expected);
  });

  test('web TTS uses the selected speed without halving it', () {
    expect(ttsSpeechRate(1.0, isWeb: true), 1.0);
    expect(ttsSpeechRate(1.5, isWeb: true), 1.5);
  });

  test('native TTS keeps the platform-normalized speech rate', () {
    expect(ttsSpeechRate(1.0, isWeb: false), 0.5);
    expect(ttsSpeechRate(1.5, isWeb: false), 0.75);
  });
}
