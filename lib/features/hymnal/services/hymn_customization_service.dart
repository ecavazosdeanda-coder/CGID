import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../content.dart';
import 'score_catalog.dart';
import 'web_score_storage.dart';

class HymnCustomizationService {
  static const _chordsPrefix = 'cgdi_custom_chords_';
  static const _scorePrefix = 'cgdi_custom_score_';

  /// Obtiene los acordes personalizados guardados para este himno si existen.
  Future<List<Section>?> getCustomChords(String hymnId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chordsPrefix$hymnId');
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw) as List;
      return [
        for (final item in decoded)
          Section.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (e) {
      debugPrint('Error leyendo acordes personalizados para $hymnId: $e');
      return null;
    }
  }

  /// Guarda una versión editada de los acordes y texto para un himno.
  Future<void> saveCustomChords(String hymnId, List<Section> sections) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode([for (final s in sections) s.toJson()]);
    await prefs.setString('$_chordsPrefix$hymnId', jsonString);
  }

  /// Restablece los acordes de este himno a los que extrae la partitura oficial.
  Future<void> clearCustomChords(String hymnId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_chordsPrefix$hymnId');
  }

  /// Verifica si el himno tiene acordes editados manualmente.
  Future<bool> hasCustomChords(String hymnId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('$_chordsPrefix$hymnId');
    } catch (e) {
      return false;
    }
  }

  /// Obtiene el XML de la partitura personalizada si el usuario subió una.
  Future<String?> getCustomScoreXml(String hymnId) async {
    try {
      if (kIsWeb) {
        final fromWeb = getCustomScoreWeb(hymnId);
        if (fromWeb != null && fromWeb.trim().isNotEmpty) return fromWeb;
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_scorePrefix$hymnId');
    } catch (e) {
      debugPrint('Error obteniendo partitura personalizada para $hymnId: $e');
      return null;
    }
  }

  /// Verifica si el himno tiene una partitura personalizada cargada.
  Future<bool> hasCustomScore(String hymnId) async {
    try {
      if (kIsWeb) {
        final webScore = getCustomScoreWeb(hymnId);
        if (webScore != null && webScore.trim().isNotEmpty) return true;
      }
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('$_scorePrefix$hymnId');
    } catch (e) {
      return false;
    }
  }

  /// Guarda una partitura MusicXML corregida (.mxl, .musicxml o .xml) subida por el usuario.
  Future<bool> saveCustomScore({
    required String hymnId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    String? xmlContent;
    final lowerName = fileName.toLowerCase();

    try {
      if (lowerName.endsWith('.mxl')) {
        // Descomprime el archivo comprimido MXL (ZIP)
        final archive = ZipDecoder().decodeBytes(bytes);
        final xmlFile = archive.files.firstWhere(
          (file) =>
              file.isFile &&
              file.name.toLowerCase().endsWith('.xml') &&
              !file.name.startsWith('META-INF/'),
        );
        xmlContent = utf8.decode(xmlFile.content as List<int>);
      } else {
        // Archivo MusicXML o XML plano
        xmlContent = utf8.decode(bytes);
      }
    } catch (e) {
      debugPrint('Error procesando archivo MusicXML subido: $e');
      return false;
    }

    if (xmlContent.trim().isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_scorePrefix$hymnId', xmlContent);

    if (kIsWeb) {
      setCustomScoreWeb(hymnId, xmlContent);
    }

    // Invalida la caché de acordes para que se recalculen desde la nueva partitura
    scoreCatalog.invalidate(hymnId);
    return true;
  }

  /// Restablece la partitura digital a la versión oficial original.
  Future<void> clearCustomScore(String hymnId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_scorePrefix$hymnId');
    if (kIsWeb) {
      removeCustomScoreWeb(hymnId);
    }
    scoreCatalog.invalidate(hymnId);
  }

  /// Descarga el archivo de partitura MusicXML (.mxl) oficial para que el músico
  /// pueda abrirlo y corregirlo en MuseScore u otro editor de partituras.
  Future<Uint8List?> getOfficialScoreBytes(String hymnId) async {
    final info = scoreCatalog[hymnId];
    if (info == null || info.files.isEmpty) return null;
    try {
      final assetKey = info.assetKeyFor(0);
      final byteData = await rootBundle.load(assetKey);
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } catch (e) {
      debugPrint('Error descargando partitura oficial: $e');
      return null;
    }
  }

  /// Descarga un archivo a la computadora o dispositivo del usuario.
  void downloadFile(Uint8List bytes, String filename) {
    if (kIsWeb) {
      triggerWebDownload(bytes, filename);
    }
  }
}

final hymnCustomizationService = HymnCustomizationService();
