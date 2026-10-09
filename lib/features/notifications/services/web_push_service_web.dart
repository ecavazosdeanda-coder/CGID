import 'dart:async';
import 'dart:js_interop';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

/// Servicio cliente de notificaciones en el navegador para cultos y avisos.
class WebPushNotificationService {
  static const String _prefEnabledKey = 'web_notifications_enabled';

  static bool get isSupported {
    try {
      return web.window.navigator.userAgent.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool get isGranted {
    try {
      return web.Notification.permission == 'granted';
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabledInPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabledKey) ?? false;
  }

  static Future<bool> requestPermission() async {
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

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);
  }

  static Future<void> showLocalReminder({
    required String title,
    required String body,
    String? meetUrl,
  }) async {
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
