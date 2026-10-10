import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  AuthService({FirebaseAuth? auth, this.firestore})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore? firestore;
  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

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
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final createdUser = cred.user;
      if (createdUser == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }
      final uid = createdUser.uid;

      // La cuenta maestra puede inicializarse sin invitación. Cualquier otra
      // cuenta necesita una invitación creada previamente por un administrador
      // o por el pastor responsable de su congregación.
      if (cleanEmail == 'ecavazosdeanda@gmail.com') {
        await _db.collection('users').doc(uid).set({
          'email': cleanEmail,
          'role': 'admin',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await sendVerificationEmail(createdUser);
    } finally {
      // Un fallo del correo no debe borrar una cuenta válida. Se puede reenviar.
      await _auth.signOut();
    }
  }

  Future<void> resendVerificationEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = credential.user;
      if (user == null) throw FirebaseAuthException(code: 'user-not-found');
      if (user.emailVerified) {
        throw FirebaseAuthException(
          code: 'email-already-verified',
          message: 'Tu correo ya está verificado. Inicia sesión.',
        );
      }
      await sendVerificationEmail(user);
    } finally {
      await _auth.signOut();
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

    // Comprobar antes de leer el perfil: las altas administrativas ya lo tienen.
    if (email != 'ecavazosdeanda@gmail.com' && !user.emailVerified) {
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Verifica tu correo antes de ingresar.',
      );
    }

    final db = _db;
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

/// Firebase acepta el envío; no garantiza la entrega en la bandeja de entrada.
Future<void> sendVerificationEmail(User user) async {
  try {
    await user.sendEmailVerification();
  } on FirebaseAuthException catch (error) {
    throw FirebaseAuthException(
      code: 'verification-email-failed',
      message: error.code == 'too-many-requests'
          ? 'La cuenta existe, pero Firebase limitó los envíos. Espera unos minutos y usa Reenviar verificación.'
          : 'La cuenta existe, pero no se pudo enviar la verificación (${error.code}). Usa Reenviar verificación con tu correo y contraseña.',
    );
  } catch (_) {
    throw FirebaseAuthException(
      code: 'verification-email-failed',
      message: 'La cuenta existe, pero no se pudo enviar la verificación. Revisa tu conexión y usa Reenviar verificación.',
    );
  }
}
