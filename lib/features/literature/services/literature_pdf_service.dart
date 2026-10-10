import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/document_model.dart';
import 'drive_document_link.dart';
import 'drive_api_config.dart';

const maxLiteraturePdfBytes = 20 * 1024 * 1024;

void validateLiteraturePdf(Uint8List bytes) {
  if (bytes.length > maxLiteraturePdfBytes) {
    throw ArgumentError('El PDF supera el máximo de 20 MB.');
  }
  if (bytes.length < 5 ||
      ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-') {
    throw ArgumentError(
      'El archivo recibido no es un PDF. Revisa los permisos de Drive y el enlace.',
    );
  }
}

abstract class LiteraturePdfCache {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

/// Hive usa el almacenamiento de la aplicación; en web, IndexedDB del origen.
/// No escribe en Descargas ni crea un enlace para exportar el archivo.
class HiveLiteraturePdfCache implements LiteraturePdfCache {
  static Future<Box<dynamic>>? _opening;
  Future<Box<dynamic>> _box() => _opening ??= () async {
    await Hive.initFlutter();
    return Hive.openBox<dynamic>('cgid_literature_pdfs_v1');
  }();
  @override
  Future<Uint8List?> read(String key) async {
    final value = (await _box()).get(key);
    return value == null ? null : Uint8List.fromList(List<int>.from(value));
  }

  @override
  Future<void> write(String key, Uint8List bytes) async =>
      (await _box()).put(key, bytes);
}

class LiteraturePdfService {
  LiteraturePdfService({
    LiteraturePdfCache? cache,
    this.transport,
    this.driveApiKey = literatureDriveApiKey,
  }) : cache = cache ?? HiveLiteraturePdfCache();
  final LiteraturePdfCache cache;
  final http.Client? transport;
  final String driveApiKey;
  String cacheKey(DocumentModel doc) =>
      '${doc.id}:${sha256.convert(utf8.encode(normalizeLiteratureUrl(doc.url ?? '')))}';

  Future<Uint8List?> downloaded(DocumentModel doc) async {
    final bytes = await cache.read(cacheKey(doc));
    if (bytes != null) validateLiteraturePdf(bytes);
    return bytes;
  }

  Future<void> saveOffline(DocumentModel doc, Uint8List bytes) async {
    validateLiteraturePdf(bytes);
    await cache.write(cacheKey(doc), bytes);
  }

  Future<Uint8List> fetch(DocumentModel doc) async {
    final source = normalizeLiteratureUrl(doc.url ?? '');
    final drive = DriveDocumentLink.tryParse(source);
    if (drive != null && driveApiKey.isEmpty) {
      throw StateError(
        'Falta configurar la API de Drive para el visor interno. No se abrirá Drive ni se activará facturación.',
      );
    }
    final uri = drive == null
        ? Uri.parse(source)
        : Uri.https('www.googleapis.com', '/drive/v3/files/${drive.fileId}', {
            'alt': 'media',
            'key': driveApiKey,
          });
    final client = transport ?? http.Client();
    try {
      return await (() async {
        final request = http.Request('GET', uri);
        if (drive?.resourceKey != null) {
          request.headers['X-Goog-Drive-Resource-Keys'] =
              '${drive!.fileId}/${drive.resourceKey}';
        }
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw StateError(
            response.statusCode == 429
                ? 'Drive alcanzó su límite de solicitudes. Intenta más tarde.'
                : 'No se pudo leer el PDF (${response.statusCode}). Debe compartirse como lector con cualquier persona que tenga el enlace y permitir descarga.',
          );
        }
        if ((response.contentLength ?? 0) > maxLiteraturePdfBytes) {
          throw ArgumentError('El PDF supera el máximo de 20 MB.');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > maxLiteraturePdfBytes) {
            throw ArgumentError('El PDF supera el máximo de 20 MB.');
          }
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        validateLiteraturePdf(bytes);
        return bytes;
      })().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw StateError(
        'La descarga tardó demasiado. Revisa tu conexión e intenta de nuevo.',
      );
    } on http.ClientException {
      throw StateError(
        'No se pudo conectar al PDF. Revisa internet y los permisos; en web el servidor debe permitir CORS.',
      );
    } finally {
      if (transport == null) client.close();
    }
  }
}
