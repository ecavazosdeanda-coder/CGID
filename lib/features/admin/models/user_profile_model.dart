class UserProfile {
  final String uid;
  final String email;
  final String role; // admin, pastor, colaborador, proyeccionista, musico
  final String? churchId; // ID único de la iglesia asignada
  final String? churchName; // Nombre visible de la iglesia asignada

  const UserProfile({
    required this.uid,
    required this.email,
    required this.role,
    this.churchId,
    this.churchName,
  });

  bool get isAdmin => role == 'admin';
  bool get isPastor => role == 'pastor';
  bool get isCollaborator => role == 'colaborador';
  bool get isProyeccionista => role == 'proyeccionista';
  bool get isMusico => role == 'musico';

  // Matriz de permisos
  bool get canManageUsers => isAdmin;
  bool get canManageTeam => isAdmin || isPastor;
  bool get canSwitchChurch => isAdmin;
  bool get canEditPlans => isAdmin || isPastor || isCollaborator;
  bool get canSyncPlansToCloud => isAdmin || isPastor || isCollaborator;
  bool get canDownloadPlansFromCloud => true;
  bool get canEditNotices => isAdmin || isPastor;
  bool get canResetDatabase => isAdmin;
  bool get canRestoreDatabase => isAdmin || isPastor;
  bool get canAccessProjection => isAdmin || isPastor || isCollaborator || isProyeccionista;
  bool get canAccessMusic => isAdmin || isPastor || isCollaborator || isMusico;
  bool get canDownloadScores => isAdmin;
  bool get canEditScores => isAdmin;

  bool canAssignRole(String targetRole) {
    if (isAdmin) return true;
    if (isPastor) {
      return targetRole == 'colaborador' ||
          targetRole == 'proyeccionista' ||
          targetRole == 'musico';
    }
    return false;
  }

  String get roleDisplayName {
    switch (role) {
      case 'admin':
        return 'Administrador General (Conferencia)';
      case 'pastor':
        return 'Pastor Local';
      case 'colaborador':
        return 'Colaborador Litúrgico';
      case 'proyeccionista':
        return 'Multimedia / Proyección';
      case 'musico':
        return 'Músico / Alabanza';
      default:
        return role.toUpperCase();
    }
  }

  factory UserProfile.fromFirestore(Map<String, dynamic> data, String uid) {
    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'sin_rol',
      churchId: data['churchId'] as String?,
      churchName: data['churchName'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'email': email,
    'role': role,
    if (churchId != null) 'churchId': churchId,
    if (churchName != null) 'churchName': churchName,
    'updatedAt': DateTime.now().toIso8601String(),
  };

  UserProfile copyWith({String? role, String? churchId, String? churchName}) {
    return UserProfile(
      uid: uid,
      email: email,
      role: role ?? this.role,
      churchId: churchId ?? this.churchId,
      churchName: churchName ?? this.churchName,
    );
  }
}
