import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Interfaz unificada de conexión para el control remoto móvil
/// Permite comunicarse vía HTTP local (Wi-Fi) o vía Cloud Bridge (Firestore)
abstract class RemoteConnection {
  Future<void> sendCommand(String command, {Map<String, dynamic>? data});
  Stream<Map<String, dynamic>> get stateStream;
  Future<Map<String, dynamic>?> fetchInitialState();
  void dispose();
}

/// Puente de conexión remota por la nube (Cloud Bridge) usando Firestore
/// Permite controlar la proyección en la web o entre redes diferentes sin IP fija.
class CloudRemoteBridge {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String collectionName = 'remote_sessions';

  static Timer? _throttleTimer;
  static Map<String, dynamic>? _lastPublishedState;
  static Map<String, dynamic>? _pendingState;
  static String? _pendingSessionId;
  static bool _isPublishing = false;

  /// Genera un código de sesión aleatorio de 10 caracteres (~50 bits).
  /// El identificador funciona también como secreto de emparejamiento, por lo
  /// que no debe derivarse de la hora ni de otros valores predecibles.
  static String generateSessionCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Sin caracteres confusos (0, O, 1, I)
    final random = Random.secure();
    return List.generate(10, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// HOST: Crea o actualiza la sesión en la nube
  static DocumentReference<Map<String, dynamic>> sessionDoc(String sessionId) {
    return _firestore
        .collection(collectionName)
        .doc(sessionId.trim().toUpperCase());
  }

  /// HOST: Publica el estado actual en la nube con Throttling
  static Future<void> publishState(
    String sessionId,
    Map<String, dynamic> state, {
    bool force = false,
  }) async {
    _pendingSessionId = sessionId;
    _pendingState = state;

    if (force) {
      _throttleTimer?.cancel();
      await _executePublish();
      return;
    }

    if (_throttleTimer?.isActive ?? false) {
      return;
    }

    _throttleTimer = Timer(const Duration(milliseconds: 250), _executePublish);
  }

  static Future<void> _executePublish() async {
    if (_pendingSessionId == null || _pendingState == null || _isPublishing) return;
    _isPublishing = true;
    final sessionId = _pendingSessionId!;
    final state = _pendingState!;
    _pendingState = null;

    // Simple diff to avoid redundant writes (deep compare map strings)
    bool hasChanged = _lastPublishedState == null ||
        _lastPublishedState!['currentTitle'] != state['currentTitle'] ||
        _lastPublishedState!['slideIndex'] != state['slideIndex'] ||
        _lastPublishedState!['blackout'] != state['blackout'] ||
        _lastPublishedState!['planCount'] != state['planCount'] ||
        _lastPublishedState!['planIndex'] != state['planIndex'];

    // Plan items only if lengths differ to avoid deep comparison cost
    if (!hasChanged &&
        _lastPublishedState!['planItems']?.length != state['planItems']?.length) {
      hasChanged = true;
    }

    if (!hasChanged) {
      _isPublishing = false;
      return;
    }

    try {
      await sessionDoc(sessionId).set({
        ...state,
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(hours: 8)),
        ),
        'hostActive': true,
      }, SetOptions(merge: true));
      _lastPublishedState = state;
    } catch (e) {
      debugPrint('SesiÃ³n no publicada: permisos/esquema ($e)');
      rethrow;
    } finally {
      _isPublishing = false;
      // if more arrived while publishing, schedule again
      if (_pendingState != null) {
        _throttleTimer = Timer(const Duration(milliseconds: 250), _executePublish);
      }
    }
  }

  /// HOST: Escucha los comandos entrantes de los celulares conectados en la subcolecciÃ³n
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  listenCommands(
    String sessionId,
    void Function(String action, Map<String, dynamic>? payload) onCommand,
  ) {
    return sessionDoc(sessionId)
        .collection('commands')
        .orderBy('timestamp')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final action = data['action'] as String?;
            if (action != null) {
              onCommand(action, data['payload'] as Map<String, dynamic>?);
            }
          }
          // Marcar procesado borrando el comando (append-only logic)
          change.doc.reference.delete().catchError((_) {});
        }
      }
    });
  }

  /// HOST: Cierra la sesión borrando los documentos
  static Future<void> closeSession(String sessionId) async {
    try {
      final docRef = sessionDoc(sessionId);
      await docRef.delete();
    } catch (_) {}
  }

  /// CLIENTE MÃ“VIL: EnvÃ­a un comando a la subcolecciÃ³n del proyector
  static Future<void> sendCommand(
    String sessionId,
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    final colRef = sessionDoc(sessionId).collection('commands');
    try {
      await colRef.add({
        'action': action,
        'payload': payload,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error enviando comando: $e');
    }
  }

  /// CLIENTE MÃ“VIL: Escucha el estado de la sesiÃ³n en tiempo real
  static Stream<Map<String, dynamic>> listenState(String sessionId) {
    return sessionDoc(sessionId).snapshots().map((snap) {
      if (!snap.exists) return <String, dynamic>{'connected': false};
      final data = snap.data() ?? <String, dynamic>{};
      
      // Parseo robusto
      final result = <String, dynamic>{
        ...data,
        'connected': data['hostActive'] == true,
        'slideIndex': (data['slideIndex'] as num?)?.toInt() ?? 0,
        'totalSlides': (data['totalSlides'] as num?)?.toInt() ?? 0,
        'planIndex': (data['planIndex'] as num?)?.toInt() ?? 0,
        'planCount': (data['planCount'] as num?)?.toInt() ?? 0,
      };

      if (data['planItems'] is List) {
         result['planItems'] = (data['planItems'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      return result;
    });
  }
}
