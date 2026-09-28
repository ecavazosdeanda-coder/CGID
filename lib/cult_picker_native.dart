import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<(String, Uint8List)?> pickCultFile(int maxBytes) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'pptx', 'ppt', 'cgidpack'],
  );
  if (file == null) return null;
  final length = await file.length();
  if (length != null && length > maxBytes) {
    throw StateError('El archivo supera 30 MB.');
  }
  return (file.name, await file.readAsBytes());
}

Future<bool> saveCultFile(
  String name,
  Uint8List bytes,
  String mimeType,
) async =>
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      mimeType: mimeType,
    ) !=
    null;
