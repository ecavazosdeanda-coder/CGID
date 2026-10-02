import 'package:flutter_test/flutter_test.dart';

import 'package:cgid/features/ai_assistant/services/gemini_service.dart';

void main() {
  test('Gemini requires a non-empty session key', () async {
    final service = GeminiService();

    expect(
      () => service.initialize('   '),
      throwsA(
        isA<GeminiServiceException>().having(
          (error) => error.message,
          'message',
          contains('API Key'),
        ),
      ),
    );
    expect(service.isInitialized, isFalse);
  });

  test(
    'Gemini session selects the production model and clears credentials',
    () async {
      final service = GeminiService();

      await service.initialize('test-session-key');
      expect(service.isInitialized, isTrue);
      expect(service.activeModelName, 'gemini-3.8-flash');

      service.clearCredentials();
      expect(service.isInitialized, isFalse);
      expect(service.activeModelName, isNull);
    },
  );

  test('sending without configuration returns a safe Spanish error', () async {
    final service = GeminiService();

    expect(
      () => service.sendMessage('Hola'),
      throwsA(
        isA<GeminiServiceException>()
            .having((error) => error.message, 'message', contains('API Key'))
            .having(
              (error) => error.toString(),
              'safe output',
              isNot(contains('{')),
            ),
      ),
    );
  });
}
