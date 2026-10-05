import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cgid/features/admin/models/user_profile_model.dart';
import 'package:cgid/features/admin/presentation/pastor_assignment_dialog.dart';
import 'package:cgid/features/admin/providers/user_profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget({
    required UserProfile profile,
    required List<dynamic> usersAndInvitations,
  }) {
    return ProviderScope(
      overrides: [
        userProfileProvider.overrideWith((ref) => Stream.value(profile)),
        allUsersProvider.overrideWith(
          (ref) => AsyncValue.data(usersAndInvitations),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: PastorAssignmentDialog(),
        ),
      ),
    );
  }

  group('User Management Panel (PastorAssignmentDialog) Widget Tests', () {
    testWidgets('renders empty state message for administrator', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const adminProfile = UserProfile(
        uid: 'admin-uid',
        email: 'admin@cgdi.org',
        role: 'admin',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          profile: adminProfile,
          usersAndInvitations: [],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Aún no hay miembros registrados.'), findsOneWidget);
      expect(find.text('Registrar Primer Miembro'), findsOneWidget);
    });

    testWidgets('renders empty state message tailored for pastor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const pastorProfile = UserProfile(
        uid: 'pastor-uid',
        email: 'pastor@cgdi.org',
        role: 'pastor',
        churchId: 'iglesia-central',
        churchName: 'Iglesia Central',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          profile: pastorProfile,
          usersAndInvitations: [],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.text('Aún no hay colaboradores, proyeccionistas ni músicos en tu congregación.'),
        findsOneWidget,
      );
      expect(find.text('Registrar colaborador / equipo'), findsNWidgets(2));
    });

    testWidgets('renders both registered users and pending invitations', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const adminProfile = UserProfile(
        uid: 'admin-uid',
        email: 'admin@cgdi.org',
        role: 'admin',
      );

      final mixedList = [
        const UserProfile(
          uid: 'user-1',
          email: 'pastor.juan@cgdi.org',
          role: 'pastor',
          churchId: 'iglesia-norte',
          churchName: 'Iglesia Norte',
        ),
        <String, dynamic>{
          'email': 'pendiente@cgdi.org',
          'role': 'colaborador',
          'churchId': 'iglesia-norte',
          'churchName': 'Iglesia Norte',
          'isInvitation': true,
        },
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          profile: adminProfile,
          usersAndInvitations: mixedList,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('pastor.juan@cgdi.org'), findsOneWidget);
      expect(find.text('pendiente@cgdi.org'), findsOneWidget);
      expect(find.text('Invitación Pendiente'), findsOneWidget);
    });
  });
}
