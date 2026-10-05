import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Activa la conexión al Firebase Emulator Suite cuando la app se compila con
/// `--dart-define=USE_FIREBASE_EMULATOR=true`.
///
/// En producción la constante es `false` y esta función no hace nada, por lo
/// que nunca se apunta accidentalmente a datos locales.
const bool useFirebaseEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');

/// Host del emulador. En el emulador de Android usa `10.0.2.2`; desde otro
/// dispositivo en la red local usa la IP del equipo que corre los emuladores.
const String firebaseEmulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: 'localhost',
);

const int authEmulatorPort = 9099;
const int firestoreEmulatorPort = 8085;
const int functionsEmulatorPort = 5001;

/// Conecta Auth y Firestore a los emuladores locales si está habilitado.
/// Debe llamarse justo después de `Firebase.initializeApp` y antes de
/// cualquier lectura o escritura.
Future<void> connectFirebaseEmulatorsIfEnabled() async {
  if (!useFirebaseEmulator) return;
  try {
    await FirebaseAuth.instance.useAuthEmulator(
      firebaseEmulatorHost,
      authEmulatorPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      firebaseEmulatorHost,
      firestoreEmulatorPort,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      firebaseEmulatorHost,
      functionsEmulatorPort,
    );
    debugPrint(
      'Firebase Emulator Suite activo en $firebaseEmulatorHost '
      '(Auth:$authEmulatorPort, Firestore:$firestoreEmulatorPort)',
    );
  } catch (e) {
    debugPrint('No fue posible conectar con los emuladores de Firebase: $e');
  }
}
