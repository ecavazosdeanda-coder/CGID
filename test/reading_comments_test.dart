import 'package:cgid/features/comments/reading_comments.dart';
import 'package:cgid/features/admin/models/user_profile_model.dart';
import 'package:cgid/features/admin/providers/user_profile_provider.dart';
import 'package:cgid/features/tenant/models/church_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const target = ReadingTarget('faith', 'f1', 'Punto de fe');
const pastor = UserProfile(
  uid: 'pastor-a',
  email: 'pastor@example.org',
  role: 'pastor',
  churchId: 'church-a',
);
const admin = UserProfile(
  uid: 'admin',
  email: 'admin@example.org',
  role: 'admin',
);
ChurchModel church(String id, String region, String state, String city) =>
    ChurchModel(
      id: id,
      regionId: region,
      name: id,
      state: state,
      city: city,
      address: '',
      latitude: 0,
      longitude: 0,
      googleMapsUrl: '',
      pastorName: '',
      defaultMeetUrl: '',
      weeklyServices: [],
    );
final churches = [
  church('church-a', 'region-1', 'Nuevo León', 'Monterrey'),
  church('church-b', 'region-2', 'Coahuila', 'Saltillo'),
];
ReadingComment comment(String id, String churchId) => ReadingComment(id, {
  'body': 'Comentario $id',
  'churchId': churchId,
  'authorId': 'pastor-a',
  'authorRole': 'pastor',
  'visible': true,
});
final comments = [comment('uno', 'church-a'), comment('dos', 'church-b')];

void main() {
  test('solo pastor y administrador pueden redactar; pastor solo gestiona su autoría e iglesia', () {
    expect(canWriteReadingComments(null), false);
    for (final role in ['colaborador', 'musico', 'proyeccionista', 'sin_rol']) {
      expect(canWriteReadingComments(pastor.copyWith(role: role)), false);
    }
    expect(canManageReadingComment(pastor, comments.first), true);
    expect(canManageReadingComment(pastor, comments.last), false);
    expect(canManageReadingComment(admin, comments.last), true);
  });
  test('sin filtros se ven todas las iglesias y regiones; filtros combinados son opcionales', () {
    expect(filterReadingComments(comments, churches).length, 2);
    expect(
      filterReadingComments(comments, churches, region: 'region-2').single.id,
      'dos',
    );
    expect(
      filterReadingComments(
        comments,
        churches,
        state: 'Nuevo León',
        city: 'Monterrey',
      ).single.id,
      'uno',
    );
    expect(
      filterReadingComments(
        comments,
        churches,
        church: 'church-a',
        region: 'region-2',
      ),
      isEmpty,
    );
  });
  test('identificadores separan literatura, citas y puntos de fe', () {
    expect(target.key, startsWith('faith_'));
    expect(
      target.key,
      const ReadingTarget('faith', 'f1', 'Título corregido').key,
    );
    expect(
      target.key,
      isNot(const ReadingTarget('literature', 'f1', 'PDF').key),
    );
  });
  for (final profile in <UserProfile?>[null, pastor, admin]) {
    testWidgets(
      'panel compacto y lectura nacional para ${profile?.role ?? 'invitado'}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProfileProvider.overrideWith((ref) => Stream.value(profile)),
              commentChurchesProvider.overrideWith((ref) async => churches),
              readingCommentsProvider(target.key)
                  .overrideWith((ref) => Stream.value(comments)),
              managedReadingCommentsProvider(target.key)
                  .overrideWith((ref) => Stream.value(comments)),
            ],
            child: const MaterialApp(
              home: Scaffold(body: ReadingCommentsButton(target: target)),
            ),
          ),
        );
        await tester.tap(find.text('Comentarios pastorales'));
        await tester.pumpAndSettle();
        expect(find.text('Comentario uno'), findsOneWidget);
        expect(find.text('Comentario dos'), findsOneWidget);
        expect(
          find.text('Comentar'),
          profile == null ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.text('Filtrar por ubicación'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Ocultar comentarios'));
        await tester.pumpAndSettle();
        expect(find.text('Comentario uno'), findsNothing);
      },
    );
  }
}
