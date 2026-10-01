import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:http/http.dart' as http;

Future<(String, Uint8List)?> pickCultFile(int maxBytes) async {
  final result = Completer<(String, Uint8List)?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.pdf,.pptx,.ppt,.cgidpack'
    ..style.display = 'none';
  // Keep the input attached until selection/cancellation. Removing it directly
  // after click breaks file selection in embedded Chromium browsers.
  var selecting = false;
  Future<void> readSelection() async {
    selecting = true;
    try {
      final file = input.files?.item(0);
      if (file == null) {
        result.complete(null);
        return;
      }
      if (file.size > maxBytes) throw StateError('El archivo supera 30 MB.');
      final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
      result.complete((file.name, bytes));
    } catch (error, stack) {
      result.completeError(error, stack);
    }
  }

  input.onchange = ((web.Event event) {
    unawaited(readSelection());
  }).toJS;
  input.addEventListener(
    'cancel',
    ((web.Event event) {
      if (!selecting && !result.isCompleted) result.complete(null);
    }).toJS,
  );
  web.document.body!.appendChild(input);
  try {
    input.click();
    return await result.future;
  } finally {
    input.remove();
  }
}

Future<bool> saveCultFile(String name, Uint8List bytes, String mimeType) async {
  if (['localhost', '127.0.0.1'].contains(Uri.base.host)) {
    final response = await http.post(
      Uri.base
          .resolve('/api/save-export')
          .replace(queryParameters: {'name': name}),
      headers: {
        'Content-Type': 'application/octet-stream',
        'X-CGID-Request': '1',
      },
      body: bytes,
    );
    if (response.statusCode != 200) {
      throw StateError(
        'No se pudo guardar la exportación local: ${response.body}',
      );
    }
    final link = web.HTMLAnchorElement()
      ..href = Uri.base.resolve(response.body).toString()
      ..download = name
      ..style.display = 'none';
    web.document.body!.appendChild(link);
    link.click();
    Timer(const Duration(seconds: 30), () => link.remove());
    return true;
  }
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.appendChild(link);
  link.click();
  // Chromium may start consuming a download after the click returns.
  // Retain its source briefly instead of revoking it immediately.
  Timer(const Duration(seconds: 30), () {
    link.remove();
    web.URL.revokeObjectURL(url);
  });
  return true;
}
