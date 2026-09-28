import 'dart:typed_data';

import 'package:hive_ce_flutter/hive_flutter.dart';

class MediaStore {
  static Future<Box<dynamic>>? _opening;
  static final cache = <String, Uint8List>{};
  static Future<Box<dynamic>> _box() => _opening ??= () async {
    await Hive.initFlutter();
    return Hive.openBox<dynamic>('cgid_media');
  }();
  static Future<void> put(String id, Uint8List bytes) async {
    await (await _box()).put(id, bytes);
    cache[id] = bytes;
  }

  static Future<Uint8List> get(String id) async {
    if (cache.containsKey(id)) return cache[id]!;
    final data = (await _box()).get(id);
    if (data == null) {
      throw StateError('Archivo importado no disponible. Vuelve a importarlo.');
    }
    return cache[id] = Uint8List.fromList(List<int>.from(data));
  }

  static Future<void> discardPartial(List<String> ids) async {
    if (ids.isEmpty) return;
    await (await _box()).deleteAll(ids);
    for (final id in ids) {
      cache.remove(id);
    }
  }
}
