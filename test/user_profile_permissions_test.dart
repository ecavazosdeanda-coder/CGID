import 'package:flutter_test/flutter_test.dart';

import 'package:cgid/features/admin/models/user_profile_model.dart';

void main() {
  test('liturgical collaborator can prepare plans without pastoral powers', () {
    const profile = UserProfile(
      uid: 'collaborator-1',
      email: 'colaborador@example.org',
      role: 'colaborador',
      churchId: 'church-1',
      churchName: 'Iglesia de Prueba',
    );

    expect(profile.canEditPlans, isTrue);
    expect(profile.canSyncPlansToCloud, isTrue);
    expect(profile.canManageTeam, isFalse);
    expect(profile.canEditNotices, isFalse);
    expect(profile.canRestoreDatabase, isFalse);
    expect(profile.canDownloadScores, isFalse);
    expect(profile.canEditScores, isFalse);
  });

  test('missing role never defaults to pastor', () {
    final profile = UserProfile.fromFirestore({
      'email': 'sinrol@example.org',
    }, 'missing-role');

    expect(profile.role, 'sin_rol');
    expect(profile.canEditPlans, isFalse);
    expect(profile.canDownloadScores, isFalse);
    expect(profile.canEditScores, isFalse);
  });

  test('only administrators can download and edit scores', () {
    const admin = UserProfile(
      uid: 'admin-1',
      email: 'admin@example.org',
      role: 'admin',
    );
    const musician = UserProfile(
      uid: 'musician-1',
      email: 'musico@example.org',
      role: 'musico',
    );

    expect(admin.canDownloadScores, isTrue);
    expect(admin.canEditScores, isTrue);
    expect(musician.canDownloadScores, isFalse);
    expect(musician.canEditScores, isFalse);
  });
}
