import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/firebase_emulator.dart';
import 'firebase_options.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content.dart';
import 'appearance.dart';
import 'glass.dart';

import 'projection_native.dart'
    if (dart.library.js_interop) 'projection_web.dart'
    as projection;
import 'stage_display.dart';

import 'features/workspace/workspace.dart';

import 'package:audio_service/audio_service.dart';

import 'audio_handler.dart';
import 'features/projection/presentation/output_screen.dart';
import 'features/projection/presentation/stream_overlay_screen.dart';
import 'features/projection/presentation/obs_dock_screen.dart';
import 'features/notes/presentation/sermon_notes_screen.dart';
import 'features/events/presentation/church_events_screen.dart';
import 'features/hymnal/services/score_catalog.dart';
import 'remote_client_screen.dart';

CgidAudioHandler? globalAudioHandler;

Future<void> syncPlatformBranding() async {
  if (kIsWeb) return;
  try {
    await const MethodChannel('org.cgid.cgid/branding')
        .invokeMethod<void>('setSabbathIcon', {'sabbath': isSabbathBranding()});
  } catch (_) {
    // Branding should never prevent the library from opening.
  }
}

const serviceTemplateIcons = <String, IconData>{
  'church': Icons.church_outlined,
  'leader': Icons.record_voice_over_outlined,
  'sermon': Icons.campaign_outlined,
  'bible': Icons.menu_book_outlined,
  'music': Icons.music_note_outlined,
  'prayer': Icons.volunteer_activism_outlined,
  'family': Icons.groups_outlined,
  'communion': Icons.breakfast_dining_outlined,
};

const serviceTemplateIconLabels = <String, String>{
  'church': 'Iglesia',
  'leader': 'Presidencia',
  'sermon': 'Predicación',
  'bible': 'Biblia',
  'music': 'Alabanza',
  'prayer': 'Oración',
  'family': 'Congregación',
  'communion': 'Cena del Señor',
};

const serviceSectionIcons = <String, IconData>{
  'Himno por elegir': Icons.music_note_outlined,
  'Lectura bíblica': Icons.menu_book_outlined,
  'Oración': Icons.volunteer_activism_outlined,
  'Lectura de mandamientos': Icons.rule_outlined,
  'Avisos': Icons.campaign_outlined,
  'Mensaje o tema': Icons.record_voice_over_outlined,
  'Ofrenda': Icons.redeem_outlined,
  'Bienvenida': Icons.waving_hand_outlined,
  'Participación especial': Icons.auto_awesome_outlined,
  'Otra sección': Icons.add_box_outlined,
};

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase for Auth, Firestore, etc.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await connectFirebaseEmulatorsIfEnabled();
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  // audio_service exposes the operating system media session on mobile/macOS
  // and the browser Media Session API on web.  Keeping web enabled is what
  // allows Bluetooth/headset and browser media keys to control playback.
  if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      globalAudioHandler = await AudioService.init(
        builder: () => CgidAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'org.cgid.channel.audio',
          androidNotificationChannelName: 'Reproducción de Himnos CGID',
          androidNotificationChannelDescription:
              'Controles de reproducción de himnos y lecturas',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // drawable/ic_notification: ícono monocromático (solo alfa)
          // requerido por Android 5.0+ para notificaciones multimedia.
          // NO usar mipmap/ic_launcher (tiene colores → aparece como bloque gris).
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
    } catch (e) {
      debugPrint('Error inicializando AudioService: $e');
    }
  }
  await syncPlatformBranding();
  try {
    await scoreCatalog.load();
  } catch (_) {
    // Keep the verified sample available if the generated catalog is absent.
  }

  final mode = await projection.initializeProjection(args);
  if (mode != 'main') {
    MediaKit.ensureInitialized();
  }
  if (mode == 'main') {
    final prefs = await SharedPreferences.getInstance();
    appThemeMode.value = prefs.getBool('darkMode') == true
        ? ThemeMode.dark
        : ThemeMode.light;
    final effectsName = prefs.getString('visualEffects');
    appVisualEffectsMode.value = effectsName == 'solid'
        ? VisualEffectsMode.solid
        : VisualEffectsMode.full;
  }
  runApp(ProviderScope(child: CgidApp(mode: mode)));
}

final _router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/overlay',
      builder: (context, state) => const StreamOverlayScreen(),
    ),
    GoRoute(
      path: '/lowerthirds',
      builder: (context, state) => const StreamOverlayScreen(),
    ),
    GoRoute(
      path: '/obs-dock',
      builder: (context, state) => const ObsDockScreen(),
    ),
    GoRoute(
      path: '/notas',
      builder: (context, state) => const SermonNotesScreen(),
    ),
    GoRoute(
      path: '/eventos',
      builder: (context, state) => const ChurchEventsScreen(),
    ),
    GoRoute(
      path: '/remoto',
      builder: (context, state) {
        final code = state.uri.queryParameters['code'];
        return RemoteClientScreen(initialSessionId: code);
      },
    ),
    GoRoute(
      path: '/:tab',
      builder: (context, state) {
        final tab = state.pathParameters['tab'] ?? 'home';
        return WorkspaceLoader(initialTab: tab);
      },
    ),
  ],
);

final _projectionRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const OutputScreen()),
  ],
);

final _stageRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const StageDisplayScreen()),
  ],
);

final _overlayRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const StreamOverlayScreen()),
    GoRoute(
      path: '/overlay',
      builder: (context, state) => const StreamOverlayScreen(),
    ),
    GoRoute(
      path: '/lowerthirds',
      builder: (context, state) => const StreamOverlayScreen(),
    ),
  ],
);

final _dockRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ObsDockScreen()),
    GoRoute(
      path: '/obs-dock',
      builder: (context, state) => const ObsDockScreen(),
    ),
  ],
);

class CgidApp extends StatelessWidget {
  final String mode;
  const CgidApp({super.key, this.mode = 'main'});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: appThemeMode,
    builder: (context, modeValue, _) =>
        ValueListenableBuilder<VisualEffectsMode>(
          valueListenable: appVisualEffectsMode,
          builder: (context, effects, _) => MaterialApp.router(
            title: 'CGID · Biblioteca y proyección',
            debugShowCheckedModeBanner: false,
            theme: cgidTheme(Brightness.light),
            darkTheme: cgidTheme(Brightness.dark),
            themeMode: modeValue,
            builder: (context, child) => VisualEffectsScope(
              mode: effects,
              child: child ?? const SizedBox.shrink(),
            ),
            routerConfig: mode == 'projection'
                ? _projectionRouter
                : mode == 'stage'
                ? _stageRouter
                : mode == 'overlay'
                ? _overlayRouter
                : mode == 'dock'
                ? _dockRouter
                : _router,
          ),
        ),
  );
}

Widget highlightSearchText(BuildContext context, String text, String query) {
  if (query.trim().isEmpty) {
    return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis);
  }
  final q = normalized(query.trim());
  final normText = normalized(text);
  final spans = <TextSpan>[];
  int start = 0;
  int idx = normText.indexOf(q);
  final TextStyle highlightStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: Theme.of(context).colorScheme.primary,
  );
  while (idx != -1) {
    if (idx > start) {
      spans.add(TextSpan(text: text.substring(start, idx)));
    }
    spans.add(
      TextSpan(
        text: text.substring(idx, idx + q.length),
        style: highlightStyle,
      ),
    );
    start = idx + q.length;
    idx = normText.indexOf(q, start);
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start)));
  }
  return Text.rich(
    TextSpan(children: spans),
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
  );
}
