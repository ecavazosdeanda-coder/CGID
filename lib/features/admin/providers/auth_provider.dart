import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> activateAccountWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cred = await _auth.createUserWithEmailAndPassword(email: cleanEmail, password: password);
    final uid = cred.user!.uid;

    // Verificar si el administrador pre-asignó una iglesia a este correo
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .get();

      if (query.docs.isNotEmpty) {
        final preDoc = query.docs.first;
        final data = preDoc.data();
        final churchId = data['churchId'] as String?;
        final churchName = data['churchName'] as String?;
        final role = data['role'] as String? ?? 'pastor';

        final profileData = <String, dynamic>{
          'email': cleanEmail,
          'role': role,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (churchId != null) profileData['churchId'] = churchId;
        if (churchName != null) profileData['churchName'] = churchName;

        await FirebaseFirestore.instance.collection('users').doc(uid).set(
              profileData,
              SetOptions(merge: true),
            );

        if (preDoc.id != uid) {
          await preDoc.reference.delete().catchError((_) {});
        }
      }
    } catch (_) {
      // Continuar si hay retraso de red
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
