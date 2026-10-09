import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// HOST: Publica el estado actual en la nube
  static Future<void> publishState(
    String sessionId,
    Map<String, dynamic> state,
  ) async {
    try {
      await sessionDoc(sessionId).set({
        ...state,
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().toUtc().add(const Duration(hours: 8)),
        ),
        'hostActive': true,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// HOST: Escucha los comandos entrantes de los celulares conectados
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
  listenCommands(
    String sessionId,
    void Function(String action, Map<String, dynamic>? payload) onCommand,
  ) {
    String? lastProcessedCmdId;
    return sessionDoc(sessionId).snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      final cmd = data['lastCommand'];
      if (cmd is Map<String, dynamic>) {
        final cmdId = cmd['id'] as String?;
        final action = cmd['action'] as String?;
        if (cmdId != null && action != null && cmdId != lastProcessedCmdId) {
          lastProcessedCmdId = cmdId;
          onCommand(action, cmd['payload'] as Map<String, dynamic>?);
        }
      }
    });
  }

  /// HOST: Cierra la sesión
  static Future<void> closeSession(String sessionId) async {
    try {
      await sessionDoc(
        sessionId,
      ).update({'hostActive': false, 'closedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// CLIENTE MÓVIL: Envía un comando a la sesión del proyector
  static Future<void> sendCommand(
    String sessionId,
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    final docRef = sessionDoc(sessionId);
    final randomPart = Random.secure().nextInt(1000000);
    final cmdId = '${DateTime.now().millisecondsSinceEpoch}_${randomPart}_$action';
    await docRef.update({
      'lastCommand': {
        'id': cmdId,
        'action': action,
        'payload': payload,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }

  /// CLIENTE MÓVIL: Escucha el estado de la sesión en tiempo real
  static Stream<Map<String, dynamic>> listenState(String sessionId) {
    return sessionDoc(sessionId).snapshots().map((snap) {
      if (!snap.exists) return <String, dynamic>{'connected': false};
      final data = snap.data() ?? <String, dynamic>{};
      return {...data, 'connected': data['hostActive'] == true};
    });
  }
}
