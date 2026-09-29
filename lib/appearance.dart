import 'package:flutter/material.dart';

import 'glass.dart';

final appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

bool isSabbathBranding([DateTime? date]) =>
    (date ?? DateTime.now()).weekday == DateTime.saturday;

String globalChurchLogoAsset = 'assets/branding/icon_silver_blue.png';
String globalChurchName = 'Conferencia General de la Iglesia de Dios';
String churchLogoAsset([DateTime? date]) => globalChurchLogoAsset;

ThemeData cgidTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff286965),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'CGID',
    materialTapTargetSize: MaterialTapTargetSize.padded,
    focusColor: scheme.primary.withValues(alpha: .18),
    colorScheme: scheme,
    extensions: [dark ? GlassTheme.dark : GlassTheme.light],
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xff203641) : const Color(0xfff8fcfa),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark ? const Color(0xff39515c) : Colors.white),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .45),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selectedTileColor: scheme.primaryContainer.withValues(alpha: .65),
      selectedColor: scheme.onPrimaryContainer,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xff20343f) : const Color(0xfff5faf7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xff20343f) : const Color(0xfff5faf7),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    scaffoldBackgroundColor: dark
        ? const Color(0xff101a22)
        : const Color(0xfff7f7f3),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff101a22) : const Color(0xfff7f7f3),
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff1b2a34) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

class ChurchLogo extends StatelessWidget {
  final double height;
  const ChurchLogo({super.key, this.height = 46});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.asset(
      churchLogoAsset(),
      height: height,
      width: height,
      fit: BoxFit.contain,
      semanticLabel: 'Logotipo de la Conferencia General de la Iglesia de Dios',
    ),
  );
}
