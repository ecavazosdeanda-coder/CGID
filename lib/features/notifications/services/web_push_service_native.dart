/// Implementación segura para plataformas donde la API Web Notification no
/// existe. Mantiene el mismo contrato que la implementación del navegador.
class WebPushNotificationService {
  static bool get isSupported => false;

  static bool get isGranted => false;

  static Future<bool> isEnabledInPrefs() async => false;

  static Future<bool> requestPermission() async => false;

  static Future<void> setEnabled(bool enabled) async {}

  static Future<void> showLocalReminder({
    required String title,
    required String body,
    String? meetUrl,
  }) async {}
}
