import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

/// Servicio cliente de notificaciones en el navegador para cultos y avisos eclesiales.
class WebPushNotificationService {
  static const String _prefEnabledKey = 'web_notifications_enabled';

  /// Comprueba si el navegador actual soporta la API de notificaciones
  static bool get isSupported {
    if (!kIsWeb) return false;
    try {
      return web.window.navigator.userAgent.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Verifica si el usuario ya concedió permisos de notificación
  static bool get isGranted {
    if (!kIsWeb) return false;
    try {
      return web.Notification.permission == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// Comprueba si las notificaciones están habilitadas en las preferencias locales
  static Future<bool> isEnabledInPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? false;
  }

  /// Solicita permisos de notificación al usuario
  static Future<bool> requestPermission() async {
    if (!kIsWeb) return false;
    try {
      final perm = await web.Notification.requestPermission().toDart;
      final granted = perm.toDart == 'granted';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabledKey, granted);
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Desactiva o activa las notificaciones desde los ajustes
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
  }

  /// Muestra una notificación local de culto si los permisos están concedidos
  static Future<void> showLocalReminder({
    required String title,
    required String body,
    String? meetUrl,
  }) async {
    if (!kIsWeb) return;
    final enabled = await isEnabledInPrefs();
    if (!enabled || !isGranted) return;

    try {
      final options = web.NotificationOptions(
        body: body,
        icon: 'icons/Icon-192.png',
        badge: 'favicon-gold.png',
        tag: 'cgdi-service-reminder',
      );
      final notification = web.Notification(title, options);
      if (meetUrl != null && meetUrl.isNotEmpty) {
        notification.onclick = ((web.Event _) {
          web.window.open(meetUrl, '_blank');
        }).toJS;
      }
    } catch (_) {}
  }
}
