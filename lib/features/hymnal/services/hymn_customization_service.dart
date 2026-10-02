import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../content.dart';
import 'score_catalog.dart';
import 'web_score_storage.dart';

class HymnCustomizationService {
  static const masterAdminEmail = 'ecavazosdeanda@gmail.com';
  static const _chordsPrefix = 'cgdi_chords_v2_';
  static const _scorePrefix = 'cgdi_custom_score_';

  static bool _cachedRoleIsAdmin = false;

  @visibleForTesting
  static void setAdminForTesting(bool value) => _cachedRoleIsAdmin = value;

  /// Determina si el usuario actualmente autenticado tiene rol de Administrador
  static bool get isAdmin {
    try {
      if (Firebase.apps.isEmpty) return _cachedRoleIsAdmin;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return _cachedRoleIsAdmin;
      final email = user.email?.trim().toLowerCase();
      if (email == masterAdminEmail) return true;
      return _cachedRoleIsAdmin;
    } catch (_) {
      return _cachedRoleIsAdmin;
    }
  }

  /// Alias de compatibilidad
  static bool get isMasterAdmin => isAdmin;

  /// Consulta Firestore para actualizar si el usuario actual posee rol de 'admin'
  static Future<bool> refreshAdminStatus() async {
    try {
      if (Firebase.apps.isEmpty) return false;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _cachedRoleIsAdmin = false;
        return false;
      }
      final email = user.email?.trim().toLowerCase();
      if (email == masterAdminEmail) {
        _cachedRoleIsAdmin = true;
        return true;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['role'] == 'admin') {
        _cachedRoleIsAdmin = true;
        return true;
      }
      _cachedRoleIsAdmin = false;
      return false;
    } catch (_) {
      _cachedRoleIsAdmin = false;
      return false;
    }
  }

  /// Obtiene los acordes personalizados guardados para este himno si existen.
  Future<List<Section>?> getCustomChords(String hymnId) async {
    List<Section>? local;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chordsPrefix$hymnId');
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        local = [
          for (final item in decoded)
            Section.fromJson(Map<String, dynamic>.from(item as Map)),
        ];
      }
    } catch (e) {
      debugPrint('Error leyendo acordes personalizados para $hymnId: $e');
    }

    // Consulta Firestore para obtener la versión publicada por el Administrador Maestro
    try {
      if (Firebase.apps.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('hymn_customizations')
            .doc(hymnId)
            .get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if (data['sections'] is List) {
            final list = data['sections'] as List;
            final cloudSections = [
              for (final item in list)
                Section.fromJson(Map<String, dynamic>.from(item as Map)),
            ];
            // Guarda en caché local para acceso sin conexión
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                '$_chordsPrefix$hymnId',
                jsonEncode([for (final s in cloudSections) s.toJson()]),
              );
            } catch (_) {}
            return cloudSections;
          }
        }
      }
    } catch (e) {
      debugPrint('Error consultando acordes en Firestore para $hymnId: $e');
    }

    return local;
  }

  /// Guarda una versión editada de los acordes y texto para un himno (solo Administrador Maestro).
  Future<bool> saveCustomChords(String hymnId, List<Section> sections) async {
    if (!isMasterAdmin) {
      debugPrint('Guardado rechazado: solo el Administrador Maestro puede guardar acordes.');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode([for (final s in sections) s.toJson()]);
    await prefs.setString('$_chordsPrefix$hymnId', jsonString);

    // Sincroniza a la nube en Firestore para que toda la congregación y músicos lo reciban
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('hymn_customizations')
            .doc(hymnId)
            .set({
          'hymnId': hymnId,
          'sections': [for (final s in sections) s.toJson()],
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': masterAdminEmail,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error sincronizando acordes a Firestore: $e');
    }
    return true;
  }

  /// Restablece los acordes de este himno a los que extrae la partitura oficial (solo Administrador Maestro).
  Future<bool> clearCustomChords(String hymnId) async {
    if (!isMasterAdmin) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_chordsPrefix$hymnId');

    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('hymn_customizations')
            .doc(hymnId)
            .update({'sections': FieldValue.delete()});
      }
    } catch (_) {}
    return true;
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

  /// Guarda una partitura MusicXML corregida (.mxl, .musicxml o .xml) subida por el usuario (solo Administrador Maestro).
  Future<bool> saveCustomScore({
    required String hymnId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!isMasterAdmin) {
      debugPrint('Subida de partitura denegada: solo el Administrador Maestro puede subir partituras.');
      return false;
    }

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

  /// Restablece la partitura digital a la versión oficial original (solo Administrador Maestro).
  Future<void> clearCustomScore(String hymnId) async {
    if (!isMasterAdmin) return;

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
