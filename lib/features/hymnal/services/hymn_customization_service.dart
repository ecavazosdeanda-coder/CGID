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

class ScoreVerification {
  final bool verified;
  final String notes;
  final String verifiedBy;
  final String verifiedAt;

  const ScoreVerification({
    this.verified = false,
    this.notes = '',
    this.verifiedBy = '',
    this.verifiedAt = '',
  });

  factory ScoreVerification.fromJson(Map<String, dynamic> json) =>
      ScoreVerification(
        verified: json['verified'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
        verifiedBy: json['verifiedBy'] as String? ?? '',
        verifiedAt: json['verifiedAt'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'verified': verified,
    'notes': notes,
    'verifiedBy': verifiedBy,
    'verifiedAt': verifiedAt,
  };
}

class HymnCustomizationService {
  static const masterAdminEmail = 'ecavazosdeanda@gmail.com';
  static const _chordsPrefix = 'cgdi_chords_v2_';
  static const _scorePrefix = 'cgdi_custom_score_';
  static const _scoreReviewPrefix = 'cgdi_score_review_v1_';

  static bool _cachedRoleIsAdmin = false;
  static String? _cachedAdminUid;

  @visibleForTesting
  static void setAdminForTesting(bool value) {
    _cachedRoleIsAdmin = value;
    if (!value) _cachedAdminUid = null;
  }

  /// Determina si el usuario actualmente autenticado tiene rol de Administrador
  static bool get isAdmin => false;

  /// Alias de compatibilidad
  static bool get isMasterAdmin => false;

  /// Consulta Firestore para actualizar si el usuario actual posee rol de 'admin'
  static Future<bool> refreshAdminStatus() async {
    return false;
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
      debugPrint(
        'Guardado rechazado: solo el Administrador Maestro puede guardar acordes.',
      );
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

  /// Lee el dictamen musical publicado para una partitura. La corrección
  /// automática nunca equivale a una verificación humana.
  Future<ScoreVerification> getScoreVerification(String hymnId) async {
    var local = const ScoreVerification();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_scoreReviewPrefix$hymnId');
      if (raw != null && raw.trim().isNotEmpty) {
        local = ScoreVerification.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (e) {
      debugPrint('Error leyendo verificación local de $hymnId: $e');
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        final document = await FirebaseFirestore.instance
            .collection('hymn_customizations')
            .doc(hymnId)
            .get();
        final rawReview = document.data()?['scoreReview'];
        if (rawReview is Map) {
          final cloud = ScoreVerification.fromJson(
            Map<String, dynamic>.from(rawReview),
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            '$_scoreReviewPrefix$hymnId',
            jsonEncode(cloud.toJson()),
          );
          return cloud;
        }
      }
    } catch (e) {
      debugPrint('Error consultando verificación de $hymnId: $e');
    }
    return local;
  }

  /// Publica el dictamen después de comparar MusicXML y escaneo original.
  Future<bool> saveScoreVerification(
    String hymnId, {
    required bool verified,
    String notes = '',
  }) async {
    if (!isMasterAdmin) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    String email = masterAdminEmail;
    try {
      email = FirebaseAuth.instance.currentUser?.email ?? masterAdminEmail;
    } catch (_) {}
    final review = ScoreVerification(
      verified: verified,
      notes: notes.trim(),
      verifiedBy: email,
      verifiedAt: now,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_scoreReviewPrefix$hymnId',
      jsonEncode(review.toJson()),
    );
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('hymn_customizations')
            .doc(hymnId)
            .set({
              'hymnId': hymnId,
              'scoreReview': review.toJson(),
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': email,
            }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error publicando verificación de $hymnId: $e');
      return false;
    }
    return true;
  }

  /// Guarda una partitura MusicXML corregida (.mxl, .musicxml o .xml) subida por el usuario (solo Administrador Maestro).
  Future<bool> saveCustomScore({
    required String hymnId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!isMasterAdmin) {
      debugPrint(
        'Subida de partitura denegada: solo el Administrador Maestro puede subir partituras.',
      );
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
    await saveScoreVerification(
      hymnId,
      verified: false,
      notes: 'Partitura reemplazada; requiere una nueva comparación con el original.',
    );
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
    await saveScoreVerification(
      hymnId,
      verified: false,
      notes: 'Se restableció la versión automática; requiere verificación.',
    );
  }

  /// Obtiene la partitura MusicXML oficial únicamente para administradores.
  ///
  /// Esta validación complementa el control de interfaz para impedir que otra
  /// ruta interna invoque la exportación sin autorización.
  Future<Uint8List?> getOfficialScoreBytes(String hymnId) async {
    if (!isAdmin) {
      debugPrint(
        'Descarga de partitura denegada: solo administradores pueden exportar MusicXML.',
      );
      return null;
    }
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
    if (!isAdmin) {
      debugPrint(
        'Exportación de partitura denegada: el usuario no es administrador.',
      );
      return;
    }
    if (kIsWeb) {
      triggerWebDownload(bytes, filename);
    }
  }
}

final hymnCustomizationService = HymnCustomizationService();
