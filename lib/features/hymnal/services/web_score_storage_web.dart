import 'dart:convert';
import 'package:web/web.dart' as web;

void setCustomScoreWeb(String key, String content) {
  try {
    web.window.localStorage.setItem('cgdi_custom_score_$key', content);
  } catch (_) {}
}

String? getCustomScoreWeb(String key) {
  try {
    return web.window.localStorage.getItem('cgdi_custom_score_$key');
  } catch (_) {
    return null;
  }
}

void removeCustomScoreWeb(String key) {
  try {
    web.window.localStorage.removeItem('cgdi_custom_score_$key');
  } catch (_) {}
}

void triggerWebDownload(List<int> bytes, String filename) {
  try {
    final base64Data = base64Encode(bytes);
    final anchor = web.HTMLAnchorElement()
      ..href = 'data:application/octet-stream;base64,$base64Data'
      ..download = filename;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } catch (_) {}
}
