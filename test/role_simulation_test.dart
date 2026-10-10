import 'dart:async';
import 'dart:convert';

import 'package:cgid/features/admin/models/user_profile_model.dart';
import 'package:cgid/features/admin/presentation/role_simulation_panel.dart';
import 'package:cgid/features/admin/presentation/notices_editor_screen.dart';
import 'package:cgid/features/admin/providers/user_profile_provider.dart';
import 'package:cgid/features/hymnal/services/hymn_customization_service.dart';
import 'package:cgid/features/tenant/models/church_model.dart';
import 'package:cgid/features/tenant/providers/tenant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const admin = UserProfile(
  uid: 'admin-test',
  email: 'admin@example.com',
  role: 'admin',
);
final testChurch = ChurchModel.fromJson({
  'id': 'church-test',
  'regionId': 'test',
  'name': 'Iglesia de pruebas',
  'state': '',
  'city': '',
  'address': '',
  'latitude': 0,
  'longitude': 0,
});

Future<ProviderContainer> session(UserProfile? profile) async {
  final container = ProviderContainer(
    overrides: [
      authenticatedUserProfileProvider.overrideWith(
        (ref) => Stream.value(profile),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(authenticatedUserProfileProvider, (_, _) {});
  container.listen(userProfileProvider, (_, _) {});
  await container.read(authenticatedUserProfileProvider.future);
  await container.read(userProfileProvider.future);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    HymnCustomizationService.suppressAdminTools = false;
    HymnCustomizationService.setAdminForTesting(false);
  });

  test('roles simulados cambian la interfaz sin cambiar cuenta real; salir restaura administrador', () async {
    final container = await session(admin);
    HymnCustomizationService.setAdminForTesting(true);
    for (final role in RoleSimulation.roles) {
      container.read(roleSimulationProvider.notifier).start(role, testChurch);
      await container.pump();
      final effective = await container.read(userProfileProvider.future);
      expect(effective?.role, role);
      expect(effective?.uid, admin.uid);
      expect(effective?.email, admin.email);
      expect(effective?.churchId, testChurch.id);
      expect(effective?.canManageUsers, isFalse);
      expect(
        effective?.canEditPlans,
        role == 'pastor' || role == 'colaborador',
      );
      expect(
        container.read(authenticatedUserProfileProvider).value,
        same(admin),
      );
      expect(HymnCustomizationService.isAdmin, isFalse);
    }
    container.read(roleSimulationProvider.notifier).stop();
    await container.pump();
    expect(await container.read(userProfileProvider.future), same(admin));
    expect(HymnCustomizationService.isAdmin, isTrue);
  });

  test(
    'usuarios no administradores y sesiones anónimas no pueden simular',
    () async {
      for (final profile in [null, admin.copyWith(role: 'pastor')]) {
        final container = await session(profile);
        expect(
          () => container
              .read(roleSimulationProvider.notifier)
              .start('musico', testChurch),
          throwsStateError,
        );
        expect(container.read(activeRoleSimulationProvider), isNull);
      }
    },
  );

  test(
    'no se pueden simular roles inventados ni promover a administrador',
    () async {
      final container = await session(admin);
      for (final role in ['admin', 'desconocido']) {
        expect(
          () => container
              .read(roleSimulationProvider.notifier)
              .start(role, testChurch),
          throwsArgumentError,
        );
      }
      expect(container.read(activeRoleSimulationProvider), isNull);
    },
  );

  test('dos sesiones de la misma cuenta mantienen roles diferentes', () async {
    final phone = await session(admin);
    final desktop = await session(admin);
    phone.read(roleSimulationProvider.notifier).start('musico', testChurch);
    desktop.read(roleSimulationProvider.notifier).start('pastor', testChurch);
    await phone.pump();
    await desktop.pump();
    expect((await phone.read(userProfileProvider.future))?.role, 'musico');
    expect((await desktop.read(userProfileProvider.future))?.role, 'pastor');
    phone.read(roleSimulationProvider.notifier).stop();
    expect(desktop.read(activeRoleSimulationProvider)?.role, 'pastor');
  });

  test(
    'cerrar sesión o perder el rol administrador termina la simulación',
    () async {
      final profiles = StreamController<UserProfile?>();
      addTearDown(profiles.close);
      final container = ProviderContainer(
        overrides: [
          authenticatedUserProfileProvider.overrideWith(
            (ref) => profiles.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(authenticatedUserProfileProvider, (_, _) {});
      container.listen(activeRoleSimulationProvider, (_, _) {});
      profiles.add(admin);
      await container.read(authenticatedUserProfileProvider.future);
      for (final next in [admin.copyWith(role: 'pastor'), null]) {
        container
            .read(roleSimulationProvider.notifier)
            .start('musico', testChurch);
        profiles.add(next);
        await container.pump();
        expect(container.read(activeRoleSimulationProvider), isNull);
        expect(container.read(roleSimulationProvider), isNull);
        expect(HymnCustomizationService.suppressAdminTools, isFalse);
        profiles.add(admin);
        await container.pump();
      }
    },
  );

  test(
    'iglesia simulada no sobrescribe la selección habitual del dispositivo',
    () async {
      final catalog = jsonDecode(
        await rootBundle.loadString('assets/data/regions_and_churches.json'),
      ) as Map<String, dynamic>;
      final churches = (catalog['churches'] as List)
          .map((item) => ChurchModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      SharedPreferences.setMockInitialValues({
        'selected_church_id': churches[0].id,
        'tenant_church_name': churches[0].name,
      });
      final container = await session(admin);
      container.listen(tenantProvider, (_, _) {});
      expect((await container.read(tenantProvider.future))?.id, churches[0].id);
      container
          .read(roleSimulationProvider.notifier)
          .start('pastor', churches[1]);
      await container.pump();
      expect((await container.read(tenantProvider.future))?.id, churches[1].id);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_church_id'), churches[0].id);
      container.read(roleSimulationProvider.notifier).stop();
      await container.pump();
      expect((await container.read(tenantProvider.future))?.id, churches[0].id);
    },
  );

  testWidgets(
    'avisos de simulación no cargan ni migran los avisos de otra iglesia',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'selected_church_id': 'usual-church',
        'local_notices': ['Aviso antiguo privado'],
        'local_notices_usual-church': ['Aviso habitual'],
        'local_notices_church-test': ['Aviso de pruebas'],
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: NoticesEditorScreen(
            churchId: 'church-test',
            migrateLegacyNotices: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aviso de pruebas'), findsOneWidget);
      expect(find.text('Aviso habitual'), findsNothing);
      expect(find.text('Aviso antiguo privado'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('local_notices_usual-church'), [
        'Aviso habitual',
      ]);
    },
  );

  testWidgets(
    'administrador simulado mantiene botón para salir, visible también en pantalla pequeña',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = (await tester.runAsync(() async {
        final device = await session(admin);
        device
            .read(roleSimulationProvider.notifier)
            .start('musico', testChurch);
        await device.pump();
        return device;
      }))!;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [RoleSimulationBanner(), RoleSimulationPanel()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('SIMULACIÓN'), findsOneWidget);
      expect(find.text('Volver a administrador'), findsOneWidget);
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(container.read(activeRoleSimulationProvider), isNull);
      expect(find.textContaining('SIMULACIÓN'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
