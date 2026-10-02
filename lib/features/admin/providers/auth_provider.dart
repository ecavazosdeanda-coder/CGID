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
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'No fue posible recuperar la cuenta autenticada.',
      );
    }

    try {
      await _ensureAuthorizedProfile(user);
    } catch (_) {
      await _auth.signOut();
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> activateAccountWithEmail({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    User? createdUser;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      createdUser = cred.user;
      final uid = createdUser!.uid;
      final db = FirebaseFirestore.instance;

      // La cuenta maestra puede inicializarse sin invitación. Cualquier otra
      // cuenta necesita una invitación creada previamente por un administrador
      // o por el pastor responsable de su congregación.
      if (cleanEmail == 'ecavazosdeanda@gmail.com') {
        await db.collection('users').doc(uid).set({
          'email': cleanEmail,
          'role': 'admin',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      await createdUser.sendEmailVerification();
      await _auth.signOut();
    } catch (_) {
      // Si ni siquiera fue posible enviar la verificación, elimina la cuenta
      // recién creada para que el usuario pueda volver a intentarlo.
      try {
        await createdUser?.delete();
      } catch (_) {
        await _auth.signOut();
      }
      rethrow;
    }
  }

  Future<void> _ensureAuthorizedProfile(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'La cuenta no tiene un correo válido.',
      );
    }

    final db = FirebaseFirestore.instance;
    final profileRef = db.collection('users').doc(user.uid);
    final existingProfile = await profileRef.get();
    if (existingProfile.exists) return;

    if (email == 'ecavazosdeanda@gmail.com') {
      await profileRef.set({
        'email': email,
        'role': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    if (!user.emailVerified) {
      await user.sendEmailVerification();
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verifica tu correo antes de ingresar.',
      );
    }

    final invitationRef = db.collection('account_invitations').doc(email);
    await db.runTransaction((transaction) async {
      final invitation = await transaction.get(invitationRef);
      if (!invitation.exists || invitation.data() == null) {
        throw FirebaseAuthException(
          code: 'invitation-not-found',
          message:
              'No existe una invitación ministerial activa para este correo.',
        );
      }

      final data = invitation.data()!;
      final role = data['role'] as String?;
      final churchId = data['churchId'] as String?;
      final churchName = data['churchName'] as String?;
      if (role == null || churchId == null || churchName == null) {
        throw FirebaseAuthException(
          code: 'invalid-invitation',
          message: 'La invitación está incompleta. Solicita al administrador que la renueve.',
        );
      }

      transaction.set(profileRef, {
        'email': email,
        'role': role,
        'churchId': churchId,
        'churchName': churchName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.delete(invitationRef);
    });
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
