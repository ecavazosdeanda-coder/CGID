import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;

import 'content.dart';
import 'media_store.dart';

class CultFiles {
  static const maxBytes = 30 * 1024 * 1024;
  static Future<Uint8List> convert(Uint8List bytes, String operation) async {
    final base = kIsWeb ? Uri.base : Uri.parse('http://127.0.0.1:8765/');
    if (!['localhost', '127.0.0.1'].contains(base.host)) {
      throw StateError(
        'PowerPoint requiere abrir CGID con el servidor local de conversión. Puedes importar o exportar PDF directamente.',
      );
    }
    try {
      final response = await http
          .post(
            base.resolve('/api/$operation'),
            headers: {
              'Content-Type': 'application/octet-stream',
              'X-CGID-Request': '1',
            },
            body: bytes,
          )
          .timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) throw StateError(response.body);
      return response.bodyBytes;
    } catch (error) {
      throw StateError(
        'No se pudo convertir con PowerPoint. Comprueba que el servidor local y PowerPoint estén disponibles. $error',
      );
    }
  }

  static Future<Entry> importPdf(
    Uint8List bytes,
    String name, {
    void Function(String)? progress,
  }) async {
    if (bytes.length > maxBytes) {
      throw StateError(
        'El archivo supera 30 MB. Divide el documento antes de importarlo.',
      );
    }
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openData(bytes);
    final ids = <String>[];
    var renderedBytes = 0;
    final prefix = 'import-${DateTime.now().microsecondsSinceEpoch}';
    try {
      if (document.pages.isEmpty || document.pages.length > 100) {
        throw StateError('Importa entre 1 y 100 páginas por archivo.');
      }
      for (final page in document.pages) {
        progress?.call(
          'Importando página ${page.pageNumber} de ${document.pages.length}…',
        );
        final scale =
            1920 / (page.width > page.height ? page.width : page.height);
        final rendered = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );
        if (rendered == null) {
          throw StateError('No se pudo leer la página ${page.pageNumber}.');
        }
        try {
          final image = await rendered.createImage();
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) throw StateError('No se pudo guardar la página.');
            renderedBytes += png.lengthInBytes;
            if (renderedBytes > 80 * 1024 * 1024) {
              throw StateError(
                'Las imágenes del documento superan 80 MB. Divide el documento para importarlo.',
              );
            }
            final id = '$prefix-${page.pageNumber}';
            await MediaStore.put(id, png.buffer.asUint8List());
            ids.add(id);
          } finally {
            image.dispose();
          }
        } finally {
          rendered.dispose();
        }
      }
      return Entry(
        id: prefix,
        title: name,
        subtitle: '${ids.length} páginas · Apariencia original',
        sections: const [],
        mediaIds: ids,
      );
    } catch (_) {
      try {
        await MediaStore.discardPartial(ids);
      } catch (_) {}
      rethrow;
    } finally {
      await document.dispose();
    }
  }

  static Future<Uint8List> exportPdf(
    List<Entry> entries, {
    int lines = 4,
    double aspect = 16 / 9,
    bool repeatChorus = true,
    int theme = 0,
    bool showTitle = true,
  }) async {
    if (entries.isEmpty) {
      throw StateError('El culto no tiene contenido para exportar.');
    }
    final document = pw.Document();
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-bold.ttf'),
    );
    final slides = entries
        .expand(
          (e) => makeSlides(
            e,
            maxLines: lines,
            columns: aspect < 1.5 ? 30 : 38,
            repeatChorus: repeatChorus,
          ),
        )
        .toList();
    if (slides.isEmpty) {
      throw StateError('El culto no tiene contenido para exportar.');
    }
    if (slides.length > 500) {
      throw StateError(
        'El culto supera 500 diapositivas. Divídelo antes de exportar.',
      );
    }
    final background = theme == 1
        ? PdfColors.black
        : theme == 2
        ? const PdfColor.fromInt(0xfffff8eb)
        : const PdfColor.fromInt(0xff102e48);
    final foreground = theme == 2
        ? const PdfColor.fromInt(0xff132536)
        : PdfColors.white;
    for (final slide in slides) {
      final image = slide.mediaId == null
          ? null
          : pw.MemoryImage(await MediaStore.get(slide.mediaId!));
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(720 * aspect, 720),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(
            color: image != null ? PdfColors.black : background,
            child: image != null
                ? pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))
                : pw.Padding(
                    padding: const pw.EdgeInsets.all(50),
                    child: pw.Column(
                      children: [
                        if (showTitle)
                          pw.Text(
                            slide.title,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 24,
                              color: foreground,
                            ),
                          ),
                        pw.Expanded(
                          child: pw.Center(
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              child: pw.Text(
                                slide.text,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: bold,
                                  fontSize: 60,
                                  height: 1.35,
                                  color: foreground,
                                ),
                              ),
                            ),
                          ),
                        ),
                        pw.Text(
                          slide.label,
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 18,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }
    return document.save();
  }

  static Future<Uint8List> exportCgidPack(
    String planName,
    List<Entry> entries,
  ) async {
    if (entries.isEmpty) {
      throw StateError('El culto no tiene contenido para exportar.');
    }
    final archive = Archive();
    final manifest = {
      'format': 'cgidpack',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'name': planName,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    // Incluir imágenes de MediaStore si existen
    final mediaIds = entries.expand((e) => e.mediaIds).toSet();
    for (final id in mediaIds) {
      try {
        final imgBytes = await MediaStore.get(id);
        archive.addFile(
          ArchiveFile('media/$id.png', imgBytes.length, imgBytes),
        );
      } catch (_) {}
    }

    final encoder = ZipEncoder();
    final zipData = encoder.encode(archive);
    return Uint8List.fromList(zipData);
  }

  static Future<Map<String, dynamic>> importCgidPack(Uint8List bytes) async {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);

    ArchiveFile? manifestFile;
    final mediaFiles = <ArchiveFile>[];

    for (final file in archive) {
      if (file.name == 'manifest.json') {
        manifestFile = file;
      } else if (file.name.startsWith('media/') && file.isFile) {
        mediaFiles.add(file);
      }
    }

    if (manifestFile == null) {
      throw StateError(
        'El archivo no es un paquete válido de CGID (.cgidpack). Falta manifest.json.',
      );
    }

    final manifestJson = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;
    final name = (manifestJson['name'] as String?)?.trim() ?? 'Culto importado';
    final entriesRaw = manifestJson['entries'] as List<dynamic>? ?? [];

    // Restaurar imágenes en MediaStore
    for (final media in mediaFiles) {
      final fileName = media.name.substring('media/'.length);
      final id = fileName.replaceAll('.png', '');
      final data = Uint8List.fromList(media.content as List<int>);
      await MediaStore.put(id, data);
    }

    final entries = entriesRaw
        .map((e) => Entry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return {
      'name': name,
      'entries': entries,
    };
  }
}
