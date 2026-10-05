import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      if (!isInitialAdmin) {
        return null;
      }
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

    return UserProfile.fromFirestore(snapshot.data()!, authUser.uid);
  });
});

/// Stream de todos los usuarios registrados
final usersStreamProvider = StreamProvider<List<UserProfile>>((ref) {
  final profileAsync = ref.watch(userProfileProvider);
  final profile = profileAsync.value;
  if (profile == null || (!profile.isAdmin && !profile.isPastor)) {
    return Stream.value([]);
  }

  Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('users');
  if (profile.isPastor) {
    final churchId = profile.churchId;
    if (churchId == null || churchId.isEmpty) return Stream.value([]);
    query = query.where('churchId', isEqualTo: churchId);
  }

  return query.snapshots().map(
    (snap) => snap.docs.map((doc) => UserProfile.fromFirestore(doc.data(), doc.id)).toList()
  );
});

/// Stream de todas las invitaciones pendientes
final invitationsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final profileAsync = ref.watch(userProfileProvider);
  final profile = profileAsync.value;
  if (profile == null || (!profile.isAdmin && !profile.isPastor)) {
    return Stream.value([]);
  }

  Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('account_invitations');
  if (profile.isPastor) {
    final churchId = profile.churchId;
    if (churchId == null || churchId.isEmpty) return Stream.value([]);
    query = query.where('churchId', isEqualTo: churchId);
  }

  return query.snapshots().map((snap) => snap.docs.map((doc) => doc.data()).toList());
});

/// Provider que combina usuarios e invitaciones
final allUsersProvider = Provider<AsyncValue<List<dynamic>>>((ref) {
  final users = ref.watch(usersStreamProvider);
  final invitations = ref.watch(invitationsStreamProvider);
  
  if (users.isLoading || invitations.isLoading) return const AsyncValue.loading();
  if (users.hasError) return AsyncValue.error(users.error!, users.stackTrace!);
  if (invitations.hasError) return AsyncValue.error(invitations.error!, invitations.stackTrace!);
  
  final combined = <dynamic>[
    ...(users.value ?? []),
    ...(invitations.value ?? []),
  ];
  return AsyncValue.data(combined);
});

/// Servicio para asignación de roles e iglesias a pastores
final userManagementServiceProvider = Provider(
  (ref) => UserManagementService(),
);

class UserManagementService {
  final _functions = FirebaseFunctions.instance;

  Future<void> assignChurchToPastor({
    required String uid,
    required String churchId,
    required String churchName,
    String? role,
  }) async {
    await _functions.httpsCallable('adminUpdateRole').call({
      'targetUid': uid,
      'churchId': churchId,
      'churchName': churchName,
      'role': role,
    });
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
    await _functions.httpsCallable('adminCreateUser').call({
      'email': email,
      'password': password,
      'churchId': churchId,
      'churchName': churchName,
      'role': role,
    });
  }

  Future<void> setPasswordForPastor({
    required String email,
    required String newPassword,
  }) async {
    try {
      await _functions.httpsCallable('adminSetPassword').call({
        'email': email,
        'newPassword': newPassword,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        throw Exception('Usuario no encontrado en Authentication.');
      }
      rethrow;
    }
  }

  Future<void> updateUserRole(String uid, String role) async {
    await _functions.httpsCallable('adminUpdateRole').call({
      'targetUid': uid,
      'role': role,
    });
  }

  Future<void> deleteUser(String uid) async {
    await _functions.httpsCallable('adminDeleteUser').call({
      'targetUid': uid,
    });
  }

  Future<void> deleteInvitation(String email) async {
    await _functions.httpsCallable('adminDeleteInvitation').call({
      'email': email,
    });
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
