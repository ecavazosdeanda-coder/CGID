import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile_model.dart';
import 'auth_provider.dart';

/// Stream del perfil del usuario actualmente autenticado
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authUser = ref.watch(authStateProvider).value;
  if (authUser == null) {
    return Stream.value(null);
  }

  final docRef = FirebaseFirestore.instance.collection('users').doc(authUser.uid);

  return docRef.snapshots().asyncMap((snapshot) async {
    if (!snapshot.exists || snapshot.data() == null) {
      final isInitialAdmin = authUser.email?.toLowerCase() == 'ecavazosdeanda@gmail.com';
      final defaultProfile = UserProfile(
        uid: authUser.uid,
        email: authUser.email ?? '',
        role: isInitialAdmin ? 'admin' : 'pastor',
        churchId: null,
        churchName: null,
      );

      try {
        await docRef.set(defaultProfile.toFirestore());
      } catch (e) {
        // En caso de que las reglas aún no permitan escritura
      }
      return defaultProfile;
    }

    return UserProfile.fromFirestore(snapshot.data()!, authUser.uid);
  });
});

/// Future de todos los usuarios registrados (con timeout para evitar congelamiento de UI)
final allUsersProvider = FutureProvider<List<UserProfile>>((ref) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .get()
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw Exception('Tiempo de espera agotado al conectar con Firestore.'),
        );
    return snapshot.docs.map((doc) => UserProfile.fromFirestore(doc.data(), doc.id)).toList();
  } catch (e) {
    debugPrint('Error en allUsersProvider: $e');
    rethrow;
  }
});

/// Servicio para asignación de roles e iglesias a pastores
final userManagementServiceProvider = Provider((ref) => UserManagementService());

class UserManagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> assignChurchToPastor({
    required String uid,
    required String churchId,
    required String churchName,
    String? role,
  }) async {
    final data = <String, dynamic>{
      'churchId': churchId,
      'churchName': churchName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (role != null) {
      data['role'] = role;
    }
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> sendPasswordResetToPastor(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> registerNewPastor({
    required String email,
    required String churchId,
    required String churchName,
    String? password,
    String role = 'pastor',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    String? createdUid;

    if (password != null && password.trim().isNotEmpty) {
      FirebaseApp? tempApp;
      try {
        final appName = 'TempAuth_${DateTime.now().millisecondsSinceEpoch}';
        tempApp = await Firebase.initializeApp(
          name: appName,
          options: Firebase.app().options,
        );
        final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
        final cred = await tempAuth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password.trim(),
        );
        createdUid = cred.user?.uid;
        await tempAuth.signOut();
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') {
          rethrow;
        }
      } finally {
        if (tempApp != null) {
          await tempApp.delete();
        }
      }
    }

    final query = await _db.collection('users').where('email', isEqualTo: cleanEmail).get();
    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.update({
        'churchId': churchId,
        'churchName': churchName,
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final docRef = createdUid != null
          ? _db.collection('users').doc(createdUid)
          : _db.collection('users').doc();

      await docRef.set({
        'email': cleanEmail,
        'role': role,
        'churchId': churchId,
        'churchName': churchName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> setPasswordForPastor({
    required String email,
    required String newPassword,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    FirebaseApp? tempApp;
    try {
      final appName = 'TempAuth_${DateTime.now().millisecondsSinceEpoch}';
      tempApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      await tempAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: newPassword.trim(),
      );
      await tempAuth.signOut();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // La cuenta ya existe en Firebase Auth. Enviamos el enlace de restablecimiento directo
        await FirebaseAuth.instance.sendPasswordResetEmail(email: cleanEmail);
        throw Exception(
          'El pastor ya tiene una cuenta creada en Firebase Auth. Por políticas de seguridad, le hemos enviado un enlace a su correo ($cleanEmail) para que establezca su nueva clave.',
        );
      }
      rethrow;
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _db.collection('users').doc(uid).update({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUser(String uid) async {
    await _db.collection('users').doc(uid).delete();
  }

  Future<void> registerNewMember({
    required String email,
    required String churchId,
    required String churchName,
    String? password,
    String role = 'pastor',
  }) =>
      registerNewPastor(
        email: email,
        churchId: churchId,
        churchName: churchName,
        password: password,
        role: role,
      );
}
