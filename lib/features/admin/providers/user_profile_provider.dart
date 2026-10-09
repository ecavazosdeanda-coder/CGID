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

  final docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(authUser.uid);

  return docRef.snapshots().asyncMap((snapshot) async {
    if (!snapshot.exists || snapshot.data() == null) {
      final isInitialAdmin =
          authUser.email?.toLowerCase() == 'ecavazosdeanda@gmail.com';
      if (isInitialAdmin) {
        final defaultProfile = UserProfile(
          uid: authUser.uid,
          email: authUser.email ?? '',
          role: 'admin',
          churchId: null,
          churchName: null,
        );
        await docRef.set(defaultProfile.toFirestore());
        return defaultProfile;
      }

      // Check for invitation
      if (authUser.email != null) {
        final invRef = FirebaseFirestore.instance
            .collection('account_invitations')
            .doc(authUser.email);
        final invSnap = await invRef.get();
        if (invSnap.exists && invSnap.data() != null) {
          final invData = invSnap.data()!;
          final profile = UserProfile(
            uid: authUser.uid,
            email: authUser.email!,
            role: invData['role'] as String? ?? 'colaborador',
            churchId: invData['churchId'] as String?,
            churchName: invData['churchName'] as String?,
          );
          await docRef.set(profile.toFirestore());
          // We can delete the invitation after consuming it
          try {
            await invRef.delete();
          } catch (_) {}
          return profile;
        }
      }

      return null;
    }

    return UserProfile.fromFirestore(snapshot.data()!, authUser.uid);
  });
});

/// Future de todos los usuarios registrados (con timeout para evitar congelamiento de UI)
final allUsersProvider = FutureProvider<List<UserProfile>>((ref) async {
  try {
    final profile = await ref.watch(userProfileProvider.future);
    if (profile == null || (!profile.isAdmin && !profile.isPastor)) {
      return const [];
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      'users',
    );
    if (profile.isPastor) {
      final churchId = profile.churchId;
      if (churchId == null || churchId.isEmpty) return const [];
      query = query.where('churchId', isEqualTo: churchId);
    }

    final snapshot = await query.get().timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw Exception(
        'Tiempo de espera agotado al conectar con Firestore.',
      ),
    );
    return snapshot.docs
        .map((doc) => UserProfile.fromFirestore(doc.data(), doc.id))
        .toList();
  } catch (e) {
    debugPrint('Error en allUsersProvider: $e');
    rethrow;
  }
});

/// Servicio para asignación de roles e iglesias a pastores
final userManagementServiceProvider = Provider(
  (ref) => UserManagementService(),
);

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

    Query<Map<String, dynamic>> existingProfileQuery = _db
        .collection('users')
        .where('email', isEqualTo: cleanEmail);
    final actorUid = FirebaseAuth.instance.currentUser?.uid;
    if (actorUid != null) {
      final actor = await _db.collection('users').doc(actorUid).get();
      if (actor.data()?['role'] != 'admin') {
        // Esta condición no es solo visual: también permite que Firestore
        // demuestre que una consulta pastoral está limitada a su iglesia.
        existingProfileQuery = existingProfileQuery.where(
          'churchId',
          isEqualTo: churchId,
        );
      }
    }

    final existingProfiles = await existingProfileQuery.get();
    if (existingProfiles.docs.isNotEmpty) {
      await existingProfiles.docs.first.reference.update({
        'churchId': churchId,
        'churchName': churchName,
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else if (createdUid != null) {
      await _db.collection('users').doc(createdUid).set({
        'email': cleanEmail,
        'role': role,
        'churchId': churchId,
        'churchName': churchName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _db
          .collection('account_invitations')
          .doc(cleanEmail)
          .delete()
          .catchError((_) {});
    } else {
      await _db.collection('account_invitations').doc(cleanEmail).set({
        'email': cleanEmail,
        'role': role,
        'churchId': churchId,
        'churchName': churchName,
        'createdAt': FieldValue.serverTimestamp(),
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
  }) => registerNewPastor(
    email: email,
    churchId: churchId,
    churchName: churchName,
    password: password,
    role: role,
  );
}
