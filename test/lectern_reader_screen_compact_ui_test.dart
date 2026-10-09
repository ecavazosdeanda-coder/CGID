import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cgid/content.dart';
import 'package:cgid/features/hymnal/presentation/lectern_reader_screen.dart';
import 'package:cgid/features/hymnal/services/hymn_customization_service.dart';

void main() {
  test('only hymns and local special hymns support chord tools', () {
    const bible = Entry(
      id: 'b0:0:1:3',
      title: 'Génesis 1:1-3',
      sections: [Section('Versículos', '1 En el principio...')],
    );
    const hymn = Entry(
      id: 'h1',
      title: 'Himno oficial',
      sections: [Section('1', 'Letra')],
    );
    const specialHymn = Entry(
      id: 'firestore-document-id',
      title: 'Himno especial',
      subtitle: 'Himno Local · Evento',
      sections: [Section('Letra', 'Letra especial')],
    );

    expect(bible.supportsChordTools, isFalse);
    expect(hymn.supportsChordTools, isTrue);
    expect(specialHymn.supportsChordTools, isTrue);
  });

  testWidgets('Bible lectern never offers chord administration', (
    WidgetTester tester,
  ) async {
    HymnCustomizationService.setAdminForTesting(true);
    addTearDown(() => HymnCustomizationService.setAdminForTesting(false));

    const bibleEntry = Entry(
      id: 'b0:0:1:3',
      title: 'Génesis 1:1-3',
      subtitle: 'Santa Biblia',
      sections: [Section('Versículos', '1 En el principio...')],
    );

    await tester.pumpWidget(
      const MaterialApp(home: LecternReaderScreen(entry: bibleEntry)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Agregar acordes'), findsNothing);
    expect(find.textContaining('Modo Administrador'), findsNothing);
    expect(find.byTooltip('Ver acordes'), findsNothing);
    expect(find.byTooltip('Editar acordes (Admin)'), findsNothing);
    expect(find.text('Tono:'), findsNothing);
  });

  testWidgets('LecternReaderScreen UI has compact layout and settings modal', (
    WidgetTester tester,
  ) async {
    // Definir tamaño de pantalla móvil estándar (390 x 844 dp)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const testEntry = Entry(
      id: 'test_1',
      title: 'Himno de Prueba 123',
      sections: [
        Section('1', 'Santo, Santo, Santo\nSeñor Omnipotente'),
        Section('Coro', 'Gloria a Dios'),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: LecternReaderScreen(entry: testEntry)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Verificar que el botón de retroceso existe y está visible en el AppBar
    expect(find.byType(BackButton), findsOneWidget);

    // 2. Verificar que el título está en el AppBar
    expect(find.text('Himno de Prueba 123'), findsOneWidget);

    // 3. Verificar que el botón de ajustes (Icons.tune) existe en el AppBar
    expect(find.byIcon(Icons.tune), findsOneWidget);

    // 4. Verificar que inicialmente la barra de tonos/transporte NO está en pantalla (sin acordes activos)
    expect(find.text('Tono:'), findsNothing);

    // 5. Tocar el botón de Ajustes (Icons.tune) y esperar que la animación del bottom sheet termine
    await tester.tap(find.byIcon(Icons.tune));
    // La animación de entrada de showModalBottomSheet dura típicamente 250-500ms
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // 6. Verificar que el modal de ajustes está completamente visible sin desbordamientos
    expect(find.text('Ajustes de lectura'), findsOneWidget);
    expect(find.text('Tamaño de letra:'), findsOneWidget);
    expect(find.text('Tema visual:'), findsOneWidget);
    expect(find.text('Columnas:'), findsOneWidget);
    expect(find.text('Pedales Bluetooth (PageFlip/AirTurn)'), findsOneWidget);

    // 7. Probar subir tamaño de letra
    expect(find.text('22 pt'), findsOneWidget);
    await tester.tap(find.byTooltip('Aumentar letra'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('24 pt'), findsOneWidget);

    // Probar bajar tamaño de letra
    await tester.tap(find.byTooltip('Reducir letra'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('22 pt'), findsOneWidget);

    // 8. Cerrar modal tocando el botón de cerrar
    await tester.tap(find.byIcon(Icons.close));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text('Ajustes de lectura'), findsNothing);
  });
}
