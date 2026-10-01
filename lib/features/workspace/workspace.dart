import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../content.dart';
import '../../slide_view.dart';
import '../../appearance.dart';
import '../../glass.dart';
import '../../playback.dart';
import '../../cult_files.dart';
import '../../media_store.dart';
import '../../remote_server.dart';
import '../../remote_client_screen.dart';
import '../../audio_manager_screen.dart';
import '../../service_templates.dart';
import '../../projection_native.dart' if (dart.library.js_interop) '../../projection_web.dart' as projection;
import '../../cult_picker_native.dart' if (dart.library.js_interop) '../../cult_picker_web.dart' as cult_picker;

import '../../countdown.dart';
import '../../stage_display.dart';
import '../../main.dart' show digitalScorePages, globalAudioHandler, serviceTemplateIcons, serviceTemplateIconLabels, serviceSectionIcons, syncPlatformBranding, highlightSearchText;
import '../meet_service/presentation/live_meet_card.dart';
import '../hymnal/presentation/digital_score_screen.dart';
import '../hymnal/presentation/entry_reader_modal.dart';
import '../hymnal/presentation/lectern_reader_screen.dart';
import '../literature/presentation/literature_screen.dart';
import '../admin/presentation/admin_dashboard_screen.dart';
import '../bulletin/utils/bulletin_pdf_generator.dart';
import 'package:printing/printing.dart';

class WorkspaceLoader extends StatefulWidget {
  const WorkspaceLoader({super.key});
  @override
  State<WorkspaceLoader> createState() => _WorkspaceLoaderState();
}

class _WorkspaceLoaderState extends State<WorkspaceLoader> {
  late final Future<(Library, SharedPreferences)> future = load();
  Future<(Library, SharedPreferences)> load() async =>
      (await Library.load(), await SharedPreferences.getInstance());
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: SelectableText(
              'No se pudo abrir la biblioteca.\n${snapshot.error}',
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Workspace(library: snapshot.data!.$1, prefs: snapshot.data!.$2);
    },
  );
}

class Workspace extends StatefulWidget {
  final Library library;
  final SharedPreferences prefs;
  const Workspace({super.key, required this.library, required this.prefs});
  @override
  State<Workspace> createState() => WorkspaceState();
}

class WorkspaceState extends State<Workspace> {
  int tab = 0,
      bibleSearchPage = 0,
      slideIndex = 0,
      book = 0,
      chapter = 0,
      startVerse = 1,
      endVerse = 1,
      slideTheme = 0,
      lines = 4;
  bool favoritesOnly = false,
      blackout = false,
      showTitle = true,
      repeatChorus = true,
      unlimitedVerses = true,
      hymnScoresOnly = false;
  int? countdownEndsAt;
  Timer? _countdownTimer;
  Timer? _brandingTimer;
  String hymnCategoryFilter = 'Todas';
  String hymnComposerFilter = 'Todos';
  String? marqueeText;
  String? videoBackgroundPath;
  final marqueeController = TextEditingController();
  final playback = PlaybackController();
  double aspect = 16 / 9;
  List<String> remoteUrls = [];
  String? selectedRemoteUrl;
  late final remoteServer = RemoteServer(
    onMove: (delta) {
      if (mounted) {
        setState(
          () => slideIndex = (slideIndex + delta).clamp(
            0,
            slides.isEmpty ? 0 : slides.length - 1,
          ),
        );
      }
      syncOutput();
    },
    onToggleBlack: () {
      if (mounted) toggleBlack();
    },
    onNextSection: () {
      if (mounted) moveSection(1);
    },
    onPrevSection: () {
      if (mounted) moveSection(-1);
    },
    onJumpToPlan: (index) {
      if (mounted && index >= 0 && index < plan.length) {
        prepare(plan[index]);
      }
    },
    onProjectVerse: (b, c, vStart, vEnd) {
      if (mounted) {
        final entry = lib.passage(b, c, vStart, vEnd);
        prepare(entry);
      }
    },
    getState: () => getRemoteState(),
  );

  Map<String, dynamic> getRemoteState() {
    final hasSlides = slides.isNotEmpty;
    final current = hasSlides && slideIndex >= 0 && slideIndex < slides.length
        ? slides[slideIndex]
        : null;
    final next = hasSlides && slideIndex + 1 < slides.length
        ? slides[slideIndex + 1]
        : null;

    // Find which plan item is currently presented
    int planIndex = -1;
    String currentNotes = '';
    if (presented != null) {
      planIndex = plan.indexWhere((e) => e.id == presented!.id);
      if (planIndex >= 0 && planIndex < plan.length) {
        currentNotes = plan[planIndex].notes;
      } else {
        currentNotes = presented!.notes;
      }
    }

    return {
      'blackout': blackout,
      'slideIndex': hasSlides ? slideIndex + 1 : 0,
      'totalSlides': slides.length,
      'currentTitle': current?.title ?? presented?.title ?? '',
      'currentLabel': current?.label ?? '',
      'currentText': current?.text ?? '',
      'nextTitle': next?.title ?? '',
      'nextLabel': next?.label ?? '',
      'nextText': next?.text ?? '',
      // Plan info
      'planIndex': planIndex,
      'planCount': plan.length,
      'planItems': plan
          .map((e) => {'id': e.id, 'title': e.title, 'notes': e.notes})
          .toList(),
      'currentNotes': currentNotes,
      // Countdown
      'countdownEndsAt': countdownEndsAt,
      // Bible book names for mobile search
      'bibleBookCount': lib.bible.length,
    };
  }

  String query = '', activePlan = 'Culto del sábado';
  final search = TextEditingController();
  final planName = TextEditingController();
  final focus = FocusNode();
  Entry? selected, presented;
  List<Entry> plan = [];
  List<SlideData> slides = [];
  Set<String> favorites = {};
  List<String> history = [];
  Map<String, dynamic> savedPlans = {};
  List<ServiceTemplate> serviceTemplates = [];
  Library get lib => widget.library;
  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get cardColor =>
      Theme.of(context).cardTheme.color ??
      Theme.of(context).colorScheme.surface;
  Color get accentPanel =>
      dark ? const Color(0xff29463e) : const Color(0xffe3ede8);
  Color get secondaryText => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get accentText =>
      dark ? const Color(0xffacd6c5) : const Color(0xff537565);
  Widget get themeButton => IconButton(
    tooltip: dark ? 'Modo claro' : 'Modo oscuro',
    icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    onPressed: () {
      appThemeMode.value = dark ? ThemeMode.light : ThemeMode.dark;
      widget.prefs.setBool('darkMode', !dark);
    },
  );
  Widget get effectsButton => IconButton(
    tooltip: appVisualEffectsMode.value == VisualEffectsMode.full
        ? 'Ambiente completo · desactivar'
        : 'Superficie sólida · activar ambiente',
    isSelected: appVisualEffectsMode.value == VisualEffectsMode.full,
    icon: const Icon(Icons.toggle_off_outlined),
    selectedIcon: const Icon(Icons.toggle_on),
    onPressed: () {
      final value = appVisualEffectsMode.value == VisualEffectsMode.full
          ? VisualEffectsMode.solid
          : VisualEffectsMode.full;
      setState(() => appVisualEffectsMode.value = value);
      widget.prefs.setString('visualEffects', value.name);
    },
  );
  @override
  void initState() {
    super.initState();
    globalChurchName =
        widget.prefs.getString('churchName') ??
        'Conferencia General de la Iglesia de Dios';
    globalChurchLogoAsset =
        widget.prefs.getString('churchLogoAsset') ??
        'assets/branding/icon_silver_blue.png';
    globalChurchSabbathLogoAsset =
        widget.prefs.getString('churchSabbathLogoAsset') ??
        'assets/branding/icon_gold_blue.png';
    favorites = (widget.prefs.getStringList('favorites') ?? []).toSet();
    history = widget.prefs.getStringList('history') ?? [];
    try {
      savedPlans = jsonDecode(widget.prefs.getString('plans') ?? '{}');
      activePlan = widget.prefs.getString('activePlan') ?? activePlan;
      plan = [
        for (final e in savedPlans[activePlan] ?? [])
          Entry.fromJson(Map<String, dynamic>.from(e)),
      ];
      final storedTemplates = jsonDecode(
        widget.prefs.getString('serviceTemplates') ?? '[]',
      );
      serviceTemplates = [
        for (final template in storedTemplates as List)
          ServiceTemplate.fromJson(Map<String, dynamic>.from(template as Map)),
      ];
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        message(
          'No se pudo leer la lista guardada. Consulta el respaldo antes de sobrescribirla.',
        );
      });
    }
    planName.text = activePlan;
    slideTheme = widget.prefs.getInt('slideTheme') ?? 0;
    selected = lib.hymns.first;
    playback.loadTracks();
    _brandingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(syncPlatformBranding());
    });
    playback.titleLookup = (id) {
      final found = lib.hymns.where((h) => h.id == id).firstOrNull;
      if (found != null) {
        return (title: found.title, subtitle: found.subtitle);
      }
      return null;
    };
    if (globalAudioHandler != null) {
      playback.attachAudioHandler(globalAudioHandler!);
    }
    playback.onHymnChanged = (newId) {
      final found = lib.hymns.where((h) => h.id == newId).firstOrNull;
      if (found != null && mounted) {
        setState(() => selected = found);
      }
    };
  }

  @override
  void dispose() {
    playback.dispose();
    _brandingTimer?.cancel();
    unawaited(remoteServer.stop());
    _countdownTimer?.cancel();
    search.dispose();
    planName.dispose();
    focus.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> persist(String key, String value) async {
    if (!await widget.prefs.setString(key, value)) {
      message('No se pudo guardar $key.');
    }
  }

  void savePlan() {
    final name = planName.text.trim().isEmpty
        ? 'Culto sin nombre'
        : planName.text.trim();
    savedPlans[name] = plan.map((e) => e.toJson()).toList();
    activePlan = name;
    persist('plans', jsonEncode(savedPlans));
    persist('activePlan', activePlan);
  }

  void addPlan(Entry entry) {
    setState(() => plan.add(entry));
    savePlan();
    message('Agregado al culto: ${entry.title}');
  }

  void favorite(Entry e) {
    setState(() {
      if (!favorites.add(e.id)) favorites.remove(e.id);
    });
    widget.prefs.setStringList('favorites', favorites.toList());
  }

  Map<String, dynamic> get outputState {
    final nextSlide = (slides.isNotEmpty && slideIndex + 1 < slides.length)
        ? slides[slideIndex + 1]
        : null;
    return {
      'slide': {
        ...currentSlide.toJson(),
        if (currentSlide.mediaId != null &&
            MediaStore.cache.containsKey(currentSlide.mediaId))
          'imageData': base64Encode(MediaStore.cache[currentSlide.mediaId]!),
      },
      if (nextSlide != null) 'nextSlide': nextSlide.toJson(),
      'blackout': blackout,
      'theme': slideTheme,
      'showTitle': showTitle,
      'aspect': aspect,
      'countdownEndsAt': countdownEndsAt,
      'marqueeText': marqueeText,
      'videoBackgroundPath': videoBackgroundPath,
    };
  }

  SlideData get currentSlide => slides.isEmpty
      ? const SlideData(
          'Conferencia General de la Iglesia de Dios',
          'CGID',
          'Bienvenidos',
        )
      : slides[slideIndex];
  Future<void> syncOutput() async {
    try {
      await projection.sendOutput(outputState);
    } catch (_) {
      message('No se pudo sincronizar la salida. Intenta abrirla de nuevo.');
    }
  }

  Future<void> prepare(Entry e) async {
    playback.stop();
    try {
      for (final id in e.mediaIds) {
        await MediaStore.get(id);
      }
    } catch (error) {
      message('$error');
      return;
    }
    if (!mounted) return;
    setState(() {
      selected = e;
      presented = e;
      slides = makeSlides(
        e,
        maxLines: lines,
        columns: aspect < 1.5 ? 30 : 38,
        repeatChorus: repeatChorus,
      );
      slideIndex = 0;
      blackout = false;
      tab = 5;
      history.remove(e.id);
      history.insert(0, e.id);
      history = history.take(30).toList();
    });
    widget.prefs.setStringList('history', history);
    syncOutput();
    focus.requestFocus();
  }

  void move(int delta) {
    if (slides.isEmpty) return;
    setState(
      () => slideIndex = (slideIndex + delta).clamp(0, slides.length - 1),
    );
    syncOutput();
  }

  void toggleBlack() {
    setState(() => blackout = !blackout);
    syncOutput();
  }

  void moveSection(int delta) {
    if (plan.isEmpty) return;
    int currentIndex = -1;
    if (presented != null) {
      currentIndex = plan.indexOf(presented!);
    }
    int newIndex = currentIndex + delta;
    if (newIndex >= 0 && newIndex < plan.length) {
      prepare(plan[newIndex]);
    }
  }

  void changeTab(int value) {
    playback.stop();
    setState(() {
      tab = value;
      query = '';
      search.clear();
      favoritesOnly = false;
      hymnCategoryFilter = 'Todas';
      hymnComposerFilter = 'Todos';
      hymnScoresOnly = false;
      if (value == 1) selected = lib.hymns.first;
      if (value == 3) selected = lib.faith.first;
    });
  }

  Future<void> openDigitalScore(Entry hymn) async {
    final scores = digitalScorePages[hymn.id];
    if (scores == null || scores.isEmpty) {
      message('La partitura digital de ${hymn.title} está en preparación.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DigitalScoreScreen(hymn: hymn, scorePages: scores),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Inicio',
      'Himnario',
      'Biblia',
      'Puntos de fe',
      'Partituras',
      'Proyección',
      'Cultos',
      'Literatura',
      'Acerca de',
      'Administración',
    ];
    const icons = [
      Icons.home_outlined,
      Icons.music_note_outlined,
      Icons.menu_book_outlined,
      Icons.auto_stories_outlined,
      Icons.library_music_outlined,
      Icons.cast,
      Icons.playlist_play,
      Icons.library_books_outlined,
      Icons.info_outline,
      Icons.admin_panel_settings_outlined,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final navWidth = 220.0 + ((textScale - 1).clamp(0, 1) * 60);
        final wide = box.maxWidth >= 950 + (navWidth - 220);
        final nav = SizedBox(
          width: navWidth,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color:
                    (Theme.of(context).extension<GlassTheme>() ??
                            (dark ? GlassTheme.dark : GlassTheme.light))
                        .borderColor,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors:
                    (Theme.of(context).extension<GlassTheme>() ??
                            (dark ? GlassTheme.dark : GlassTheme.light))
                        .navigationColors,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 28, 12, 4),
                    child: Row(
                      children: [
                        ChurchLogo(height: 46),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'CGID',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(25, 0, 20, 26),
                    child: Text(
                      'BIBLIOTECA Y PROYECCIÓN',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.6,
                        color: Color(0xffa5c2d1),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          if (kIsWeb || i != 7)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 3,
                              ),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                selected: tab == i,
                                selectedTileColor: const Color(0xff2c4d60),
                                textColor: const Color(0xffc0d0da),
                                iconColor: const Color(0xffc0d0da),
                                selectedColor: Colors.white,
                                leading: Icon(icons[i], size: 21),
                                title: Text(
                                  labels[i],
                                  style: const TextStyle(fontSize: 14),
                                ),
                                onTap: () {
                                  changeTab(i);
                                  if (!wide) Navigator.pop(context);
                                },
                              ),
                            ),
                      ],
                    ),
                  ),
                  if (!kIsWeb)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Biblioteca local\nDisponible sin internet',
                        style: TextStyle(
                          color: Color(0xffa9c7b7),
                          height: 1.8,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.digit1, alt: true): () =>
                changeTab(0),
            const SingleActivator(LogicalKeyboardKey.digit2, alt: true): () =>
                changeTab(1),
            const SingleActivator(LogicalKeyboardKey.digit3, alt: true): () =>
                changeTab(2),
            const SingleActivator(LogicalKeyboardKey.digit4, alt: true): () =>
                changeTab(3),
            const SingleActivator(LogicalKeyboardKey.digit5, alt: true): () =>
                changeTab(4),
            const SingleActivator(LogicalKeyboardKey.digit6, alt: true): () =>
                changeTab(5),
            const SingleActivator(LogicalKeyboardKey.digit7, alt: true): () =>
                changeTab(6),
            const SingleActivator(LogicalKeyboardKey.digit8, alt: true): () =>
                changeTab(kIsWeb ? 7 : 8),
          },
          child: Focus(
            autofocus: true,
            child: AmbientBackground(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
                appBar: wide
                    ? null
                    : AppBar(
                        title: Row(
                          children: [
                            const ChurchLogo(height: 32),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'CGID · ${labels[tab]}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          if (Theme.of(context).platform ==
                                  TargetPlatform.android ||
                              Theme.of(context).platform == TargetPlatform.iOS)
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: 'Control Remoto Móvil',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RemoteClientScreen(),
                                ),
                              ),
                            ),
                          if (!kIsWeb)
                            IconButton(
                              icon: const Icon(Icons.cloud_download_outlined),
                              tooltip: 'Gestor de Audios',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AudioManagerScreen(
                                    totalCatalogAudios: lib.hymns.length,
                                  ),
                                ),
                              ),
                            ),
                          effectsButton,
                          themeButton,
                        ],
                      ),
                body: Row(
                  children: [
                    if (wide) nav,
                    Expanded(
                      child: Column(
                        children: [
                          if (wide)
                            Container(
                              height: 76,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface
                                    .withValues(alpha: .55),
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    labels[tab],
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (!kIsWeb)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.cloud_download_outlined,
                                      ),
                                      tooltip: 'Gestor de Audios',
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AudioManagerScreen(
                                            totalCatalogAudios:
                                                lib.hymns.length,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  const ChurchLogo(height: 42),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      'Conferencia General de la Iglesia de Dios',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  effectsButton,
                                  themeButton,
                                ],
                              ),
                            ),
                          Expanded(
                            child: switch (tab) {
                              0 => home(),
                              1 => catalog(lib.hymns),
                              2 => bible(),
                              3 => catalog(lib.faith),
                              4 => scores(),
                              5 => projector(),
                              6 => servicePlan(),
                              7 => const LiteratureScreen(),
                              8 => about(),
                              9 => const AdminDashboardScreen(),
                              _ => about(),
                            },
                          ),
                          GlobalBottomPlayer(
                            controller: playback,
                            lib: lib,
                            onOpenHymn: openEntry,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget home() => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      const LiveMeetCard(),
      const SizedBox(height: 24),
      GlassSurface(
        blur: true,
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UN ESPACIO PARA LA FE Y LA ALABANZA',
              style: TextStyle(
                letterSpacing: 2,
                fontSize: 11,
                color: accentText,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'La palabra y el canto,\nsiempre a tu alcance.',
              style: TextStyle(
                fontSize: 36,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : const Color(0xff183e43),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Prepara el culto, encuentra un pasaje y comparte la alabanza con tu congregación.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => changeTab(1),
                  icon: const Icon(Icons.music_note),
                  label: const Text('Explorar himnario'),
                ),
                OutlinedButton.icon(
                  onPressed: () => changeTab(6),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Preparar culto'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          module('316', 'Himnos', Icons.music_note, 1),
          module('66', 'Libros de la Biblia', Icons.menu_book, 2),
          module('40', 'Puntos de fe', Icons.auto_stories, 3),
          module(
            '${digitalScorePages.length}',
            'Partituras digitales',
            Icons.library_music,
            4,
          ),
        ],
      ),
      const SizedBox(height: 30),
      const Text(
        'A mano para el próximo culto',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.playlist_play),
        title: Text(activePlan),
        subtitle: Text(
          '${plan.length} elementos · Guardado en este dispositivo',
        ),
        trailing: const Icon(Icons.arrow_forward),
        onTap: () => changeTab(6),
      ),
      if (history.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text(
          'Usados recientemente',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        for (final id in history.take(5))
          for (final e in [...lib.hymns, ...lib.faith].where((e) => e.id == id))
            ListTile(
              title: Text(e.title),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => prepare(e),
            ),
      ],
    ],
  );
  Widget module(String count, String label, IconData icon, int index) =>
      SizedBox(
        width: 220,
        child: Card(
          elevation: 0,
          color: cardColor,
          child: InkWell(
            onTap: () => changeTab(index),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: accentText),
                  const SizedBox(height: 18),
                  Text(
                    count,
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(label, style: TextStyle(color: secondaryText)),
                ],
              ),
            ),
          ),
        ),
      );
  String hymnCategory(Entry hymn) => hymn.subtitle.split(' · ').first;

  String hymnComposer(Entry hymn) {
    final match = RegExp(
      r'm[úu]sica\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(hymn.subtitle);
    return match?.group(1)?.trim().isNotEmpty == true
        ? match!.group(1)!.trim()
        : 'No especificado';
  }

  void openEntry(Entry e) {
    setState(() => selected = e);
    if (MediaQuery.sizeOf(context).width <= 1120) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EntryReaderModal(
            initialEntry: e,
            playback: playback,
            lib: lib,
            readerBuilder: (entry, {modal = true}) =>
                reader(entry, modal: modal),
          ),
        ),
      );
    }
  }

  Widget catalog(List<Entry> all) {
    final isHymnal = all.isNotEmpty && all.first.id.startsWith('h');
    final categories = isHymnal
        ? (all.map(hymnCategory).toSet().toList()..sort())
        : const <String>[];
    final composers = isHymnal
        ? (all.map(hymnComposer).toSet().toList()..sort())
        : const <String>[];
    final results = all
        .where(
          (e) =>
              (!favoritesOnly || favorites.contains(e.id)) &&
              (!isHymnal ||
                  hymnCategoryFilter == 'Todas' ||
                  hymnCategory(e) == hymnCategoryFilter) &&
              (!isHymnal ||
                  hymnComposerFilter == 'Todos' ||
                  hymnComposer(e) == hymnComposerFilter) &&
              (!isHymnal ||
                  !hymnScoresOnly ||
                  digitalScorePages.containsKey(e.id)) &&
              (query.isEmpty || e.searchable.contains(normalized(query))),
        )
        .toList();
    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: TextField(
            controller: search,
            decoration: const InputDecoration(
              hintText: 'Número, título o palabras…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${results.length} resultados'),
              FilterChip(
                label: const Text('Favoritos'),
                selected: favoritesOnly,
                onSelected: (v) => setState(() => favoritesOnly = v),
              ),
              if (isHymnal)
                FilterChip(
                  label: const Text('Con partitura digital'),
                  selected: hymnScoresOnly,
                  onSelected: (v) => setState(() => hymnScoresOnly = v),
                ),
              if (isHymnal)
                DropdownButton<String>(
                  isExpanded: true,
                  value: hymnCategoryFilter,
                  items: [
                    const DropdownMenuItem(
                      value: 'Todas',
                      child: Text('Tipo: todos'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => hymnCategoryFilter = value!),
                ),
              if (isHymnal)
                DropdownButton<String>(
                  isExpanded: true,
                  value: hymnComposerFilter,
                  items: [
                    const DropdownMenuItem(
                      value: 'Todos',
                      child: Text('Compositor: todos'),
                    ),
                    for (final composer in composers)
                      DropdownMenuItem(
                        value: composer,
                        child: Text(
                          composer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => hymnComposerFilter = value!),
                ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('No se encontraron coincidencias.'))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final e = results[i];
                    return ListTile(
                      selected: selected?.id == e.id,
                      leading: CircleAvatar(
                        backgroundColor: accentPanel,
                        child: Text(
                          e.id.startsWith('hrecording')
                              ? '?'
                              : e.id.substring(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(e.title, maxLines: 2),
                      subtitle: Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Favorito',
                        icon: Icon(
                          favorites.contains(e.id)
                              ? Icons.star
                              : Icons.star_border,
                        ),
                        onPressed: () => favorite(e),
                      ),
                      onTap: () {
                        openEntry(e);
                      },
                    );
                  },
                ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, b) => Padding(
        padding: const EdgeInsets.all(18),
        child: b.maxWidth > 900
            ? Row(
                children: [
                  SizedBox(
                    width: 390,
                    child: GlassSurface(radius: 20, child: list),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassSurface(
                      radius: 20,
                      child: reader(selected ?? all.first),
                    ),
                  ),
                ],
              )
            : GlassSurface(radius: 20, child: list),
      ),
    );
  }

  Widget reader(Entry e, {bool modal = false}) => ListView(
    padding: const EdgeInsets.all(30),
    children: [
      Text(
        e.id.startsWith('h')
            ? 'HIMNARIO · CANTAD A DIOS CÁNTICO NUEVO'
            : 'DOCTRINA · EDICIÓN DE 1977',
        style: TextStyle(fontSize: 10, letterSpacing: 1.5, color: accentText),
      ),
      const SizedBox(height: 14),
      Text(
        e.title,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(e.subtitle, style: TextStyle(color: secondaryText, height: 1.5)),
      const SizedBox(height: 22),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: e.sections.isEmpty
                ? null
                : () {
                    if (modal) Navigator.pop(context);
                    prepare(e);
                  },
            icon: const Icon(Icons.cast),
            label: const Text('Preparar proyección'),
          ),
          OutlinedButton.icon(
            onPressed: e.sections.isEmpty ? null : () => addPlan(e),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Agregar al culto'),
          ),
          OutlinedButton.icon(
            onPressed: e.sections.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LecternReaderScreen(entry: e),
                    ),
                  ),
            icon: const Icon(Icons.auto_stories),
            label: const Text('Modo Atril / Lectura'),
          ),
          if (e.id.startsWith('h'))
            TextButton.icon(
              onPressed: digitalScorePages.containsKey(e.id)
                  ? () => openDigitalScore(e)
                  : null,
              icon: Icon(
                digitalScorePages.containsKey(e.id)
                    ? Icons.music_note
                    : Icons.schedule,
              ),
              label: Text(
                digitalScorePages.containsKey(e.id)
                    ? 'Ver partitura digital'
                    : 'Partitura digital en preparación',
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      PlaybackControls(
        key: ValueKey('media-${e.id}'),
        controller: playback,
        contentId: e.id,
        text: e.spokenText,
        hymn: e.id.startsWith('h'),
      ),
      const SizedBox(height: 20),
      for (final s in e.sections) ...[
        Text(
          s.label,
          style: TextStyle(fontWeight: FontWeight.w700, color: accentText),
        ),
        const SizedBox(height: 8),
        SelectableText(
          s.text,
          style: const TextStyle(fontSize: 20, height: 1.7),
        ),
        const SizedBox(height: 24),
      ],
      if (e.id.startsWith('f')) ...[
        const Text(
          'Referencias bíblicas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ref in lib.references(
              e.sections.map((s) => s.text).join(' '),
            ))
              ActionChip(
                label: Text(ref.title),
                onPressed: () =>
                    showPassageDialog(context, ref, popModal: modal),
              ),
          ],
        ),
      ],
    ],
  );
  void showPassageDialog(
    BuildContext sourceContext,
    Entry entry, {
    bool popModal = false,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.title),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in entry.sections) ...[
                SelectableText(
                  s.text,
                  style: const TextStyle(fontSize: 18, height: 1.5),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.menu_book),
            label: const Text('Ir a la Biblia'),
            onPressed: () {
              Navigator.pop(dialogContext);
              if (popModal) Navigator.pop(sourceContext);
              final parts = entry.id
                  .substring(1)
                  .split(':')
                  .map(int.parse)
                  .toList();
              setState(() {
                tab = 2;
                book = parts[0];
                chapter = parts[1];
                startVerse = parts[2];
                endVerse = parts[3];
                unlimitedVerses = false;
                query = '';
                search.clear();
                playback.stop();
              });
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.cast),
            label: const Text('Proyectar'),
            onPressed: () {
              Navigator.pop(dialogContext);
              if (popModal) Navigator.pop(sourceContext);
              prepare(entry);
            },
          ),
        ],
      ),
    );
  }

  Future<void> showConcordance(int verse) async {
    final references = lib.concordance(book, chapter, verse);
    final source = lib.passage(book, chapter, verse, verse);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            shrinkWrap: true,
            children: [
              Text(
                'Concordancia bíblica',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(source.title, style: TextStyle(color: secondaryText)),
              const SizedBox(height: 16),
              if (references.isEmpty)
                const Text('No hay citas relacionadas para este versículo.'),
              for (final reference in references)
                Builder(
                  builder: (_) {
                    final target = lib.passage(
                      reference.book,
                      reference.chapter,
                      reference.start,
                      reference.end,
                    );
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(target.title),
                        subtitle: Text(
                          target.sections.map((s) => s.text).join(' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          showPassageDialog(
                            sheetContext,
                            target,
                            popModal: true,
                          );
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Text(
                'Concordancias: OpenBible.info · CC BY 4.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget bible() {
    final books = lib.bible;
    final chapters = books[book]['chapters'] as List;
    final verses = chapters[chapter]['verses'] as List;
    final effectiveEnd = unlimitedVerses
        ? verses.last['number'] as int
        : endVerse;
    final entry = lib.passage(book, chapter, startVerse, effectiveEnd);
    final matches = <Entry>[];
    if (query.trim().length >= 3) {
      final q = normalized(query);
      for (var bi = 0; bi < books.length; bi++) {
        final cs = books[bi]['chapters'] as List;
        for (var ci = 0; ci < cs.length; ci++) {
          for (final v in cs[ci]['verses']) {
            if (normalized(v['text']).contains(q)) {
              matches.add(lib.passage(bi, ci, v['number'], v['number']));
            }
          }
        }
      }
    }
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        AmbientSectionHeader(
          icon: Icons.menu_book_outlined,
          title: 'Las Sagradas Escrituras',
          subtitle: lib.bibleEdition,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar en la Biblia (mínimo 3 caracteres)',
          ),
          onChanged: (v) => setState(() {
            query = v;
            bibleSearchPage = 0;
          }),
        ),
        const SizedBox(height: 18),
        if (query.isNotEmpty) ...[
          Text(
            query.trim().length < 3
                ? 'Escribe al menos 3 caracteres.'
                : '${matches.length} resultados encontrados',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (final e in matches.skip(bibleSearchPage * 50).take(50))
            ListTile(
              title: Text(e.title),
              subtitle: highlightSearchText(
                context,
                e.sections.first.text,
                query,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.cast),
                onPressed: () => prepare(e),
              ),
              onTap: () {
                final parts = e.id
                    .substring(1)
                    .split(':')
                    .map(int.parse)
                    .toList();
                setState(() {
                  book = parts[0];
                  chapter = parts[1];
                  startVerse = parts[2];
                  endVerse = parts[3];
                  unlimitedVerses = false;
                  query = '';
                  search.clear();
                });
              },
            ),
          if (matches.length > 50)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: bibleSearchPage > 0
                        ? () => setState(() => bibleSearchPage--)
                        : null,
                  ),
                  DropdownButton<int>(
                    value: bibleSearchPage,
                    items: [
                      for (
                        var page = 0;
                        page < (matches.length / 50).ceil();
                        page++
                      )
                        DropdownMenuItem(
                          value: page,
                          child: Text(
                            'Página ${page + 1} de ${(matches.length / 50).ceil()}',
                          ),
                        ),
                    ],
                    onChanged: (page) {
                      if (page != null) setState(() => bibleSearchPage = page);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: (bibleSearchPage + 1) * 50 < matches.length
                        ? () => setState(() => bibleSearchPage++)
                        : null,
                  ),
                ],
              ),
            ),
        ] else ...[
          GlassSurface(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    DropdownButton<int>(
                      value: book,
                      items: [
                        for (var i = 0; i < books.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(books[i]['name']),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        book = v!;
                        playback.stop();
                        chapter = 0;
                        startVerse = endVerse = 1;
                        unlimitedVerses = true;
                      }),
                    ),
                    DropdownButton<int>(
                      value: chapter,
                      items: [
                        for (var i = 0; i < chapters.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text('Capítulo ${i + 1}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        chapter = v!;
                        playback.stop();
                        startVerse = endVerse = 1;
                        unlimitedVerses = true;
                      }),
                    ),
                    DropdownButton<int>(
                      value: startVerse,
                      items: [
                        for (final v in verses)
                          DropdownMenuItem(
                            value: v['number'] as int,
                            child: Text('Desde ${v['number']}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        startVerse = v!;
                        playback.stop();
                        if (endVerse < startVerse) endVerse = startVerse;
                      }),
                    ),
                    DropdownButton<int>(
                      key: const ValueKey('bible-until'),
                      value: unlimitedVerses ? 0 : endVerse,
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Hasta: sin límite'),
                        ),
                        for (final v in verses.where(
                          (v) => v['number'] >= startVerse,
                        ))
                          DropdownMenuItem(
                            value: v['number'] as int,
                            child: Text('Hasta ${v['number']}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        unlimitedVerses = v == 0;
                        playback.stop();
                        if (v != 0) endVerse = v!;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => prepare(entry),
                      icon: const Icon(Icons.cast),
                      label: const Text('Proyectar selección'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => addPlan(entry),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Agregar al culto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LecternReaderScreen(entry: entry),
                        ),
                      ),
                      icon: const Icon(Icons.auto_stories),
                      label: const Text('Modo Atril / Lectura'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (unlimitedVerses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Desde el versículo $startVerse hasta el final del capítulo.',
                style: TextStyle(color: secondaryText),
              ),
            ),
          PlaybackControls(
            controller: playback,
            contentId: entry.id,
            text: entry.spokenText,
          ),
          const SizedBox(height: 18),
          for (final v in verses.where(
            (v) => v['number'] >= startVerse && v['number'] <= effectiveEnd,
          ))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: v['number'] >= startVerse && v['number'] <= effectiveEnd
                  ? accentPanel
                  : null,
              child: ListTile(
                onTap: () => setState(() {
                  startVerse = endVerse = v['number'];
                  playback.stop();
                  unlimitedVerses = false;
                }),
                leading: Text(
                  '${v['number']}',
                  style: TextStyle(
                    color: accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                title: SelectableText(
                  (v['text'] as String).isEmpty
                      ? 'Esta edición no presenta texto independiente para este número.'
                      : v['text'],
                  style: const TextStyle(fontSize: 18, height: 1.65),
                ),
                trailing: IconButton(
                  tooltip: 'Ver concordancias',
                  icon: const Icon(Icons.link),
                  onPressed:
                      lib.concordance(book, chapter, v['number'] as int).isEmpty
                      ? null
                      : () => showConcordance(v['number'] as int),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget scores() {
    final available = lib.hymns
        .where((e) => digitalScorePages.containsKey(e.id))
        .where(
          (e) =>
              query.isEmpty || normalized(e.title).contains(normalized(query)),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const AmbientSectionHeader(
          icon: Icons.library_music_outlined,
          title: 'Partituras',
          subtitle: 'Notación musical digital que puedes ampliar sin perder nitidez, sin abrir el PDF original.',
        ),
        const SizedBox(height: 24),
        Card(
          color: accentPanel,
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.auto_awesome),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Los 316 cantos ya fueron convertidos a MusicXML con Audiveris. Son versiones iniciales: verifica notas, ritmo y letra antes de utilizarlas oficialmente.',
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: search,
          onChanged: (value) => setState(() => query = value.trim()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar por número o título',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${available.length} disponibles',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final e in available)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.music_note)),
              title: Text(e.title),
              subtitle: Text(
                '${digitalScorePages[e.id]!.length} ${digitalScorePages[e.id]!.length == 1 ? 'parte' : 'partes'} · MusicXML · Requiere revisión',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openDigitalScore(e),
            ),
          ),
      ],
    );
  }

  Widget projector() => Focus(
    focusNode: focus,
    onKeyEvent: (node, event) {
      if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.space) {
        move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        move(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        toggleBlack();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        GlassSurface(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: projection.supportsOutput
                    ? () async {
                        try {
                          await projection.openOutput(outputState);
                          message(
                            'Mueve la ventana al proyector con escritorio extendido. F11 activa pantalla completa.',
                          );
                          focus.requestFocus();
                        } catch (e) {
                          message('$e');
                        }
                      }
                    : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir proyector'),
              ),
              FilledButton.icon(
                onPressed: projection.supportsOutput
                    ? () async {
                        try {
                          await projection.openStage(outputState);
                          message(
                            'Mueve la ventana al monitor de escenario. F11 activa pantalla completa.',
                          );
                          focus.requestFocus();
                        } catch (e) {
                          message('$e');
                        }
                      }
                    : null,
                icon: const Icon(Icons.monitor),
                label: const Text('Monitor de atril'),
              ),
              OutlinedButton.icon(
                onPressed: toggleBlack,
                icon: Icon(blackout ? Icons.visibility_off : Icons.visibility),
                label: Text(
                  blackout ? 'Restaurar imagen' : 'Pantalla negra (B)',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  if (countdownEndsAt != null) {
                    _countdownTimer?.cancel();
                    setState(() => countdownEndsAt = null);
                    syncOutput();
                  } else {
                    showDialog<int>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: const Text('Temporizador de inicio'),
                        children: [
                          for (final min in [1, 2, 5, 10, 15])
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, min),
                              child: Text('$min minutos'),
                            ),
                        ],
                      ),
                    ).then((val) {
                      if (val != null) {
                        _countdownTimer?.cancel();
                        _countdownTimer = Timer(Duration(minutes: val), () {
                          if (mounted && countdownEndsAt != null) {
                            setState(() {
                              countdownEndsAt = null;
                              slideIndex = 0;
                              blackout = false;
                            });
                            syncOutput();
                          }
                        });
                        setState(() {
                          countdownEndsAt = DateTime.now()
                              .add(Duration(minutes: val))
                              .millisecondsSinceEpoch;
                        });
                        syncOutput();
                      }
                    });
                  }
                },
                icon: Icon(
                  countdownEndsAt != null ? Icons.timer_off : Icons.timer,
                ),
                label: Text(
                  countdownEndsAt != null ? 'Detener reloj' : 'Temporizador',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (kIsWeb) {
                    message(
                      'El servidor de control remoto local no se puede iniciar en la versión web por restricciones del navegador. Por favor, descarga la app de Windows o Android para usar esta función.',
                    );
                    return;
                  }
                  if (remoteUrls.isEmpty) {
                    final urls = await remoteServer.start();
                    if (urls.isNotEmpty && mounted) {
                      setState(() {
                        remoteUrls = urls;
                        selectedRemoteUrl = urls.first;
                      });
                    } else {
                      message(
                        'No se pudo iniciar el servidor. Verifica tu conexión de red.',
                      );
                      return;
                    }
                  }
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setDialogState) => AlertDialog(
                        title: const Text('Control Remoto Local'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Escanea este código QR con tu celular usando la app (ícono superior de cámara):',
                            ),
                            const SizedBox(height: 10),
                            if (remoteUrls.length > 1)
                              DropdownButton<String>(
                                value: selectedRemoteUrl,
                                isExpanded: true,
                                items: remoteUrls
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(
                                      () => selectedRemoteUrl = val,
                                    );
                                    setState(() => selectedRemoteUrl = val);
                                  }
                                },
                              ),
                            const SizedBox(height: 10),
                            Container(
                              color: Colors.white,
                              padding: const EdgeInsets.all(16),
                              child: QrImageView(
                                data: selectedRemoteUrl!,
                                version: QrVersions.auto,
                                size: 200.0,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              selectedRemoteUrl!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(),
                            StreamBuilder<String?>(
                              stream: remoteServer.onConnectionChanged,
                              builder: (context, snapshot) {
                                final ip = snapshot.data;
                                return Column(
                                  children: [
                                    if (ip != null) ...[
                                      Text(
                                        '?? Dispositivo conectado: $ip',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextButton.icon(
                                        onPressed: () =>
                                            remoteServer.disconnectDevice(),
                                        icon: const Icon(
                                          Icons.phonelink_erase,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'Desconectar / Echar',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ] else
                                      const Text(
                                        'Esperando conexión...',
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                        actions: [
                          if (Theme.of(context).platform ==
                              TargetPlatform.windows)
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  await Process.run('powershell', [
                                    '-Command',
                                    'Start-Process',
                                    'powershell',
                                    '-Verb',
                                    'RunAs',
                                    '-ArgumentList',
                                    '"-Command Set-NetConnectionProfile -NetworkCategory Private"',
                                  ]);
                                } catch (_) {}
                              },
                              icon: const Icon(
                                Icons.security,
                                color: Colors.blue,
                              ),
                              label: const Text(
                                'Hacer red privada',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                          TextButton(
                            onPressed: () {
                              unawaited(remoteServer.stop());
                              setState(() {
                                remoteUrls = [];
                                selectedRemoteUrl = null;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Apagar servidor'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cerrar'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                icon: Icon(
                  remoteUrls.isNotEmpty
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off,
                ),
                label: Text(
                  remoteUrls.isNotEmpty ? 'Remoto activo' : 'Control Remoto',
                ),
              ),
              Text(
                '${slides.isEmpty ? 0 : slideIndex + 1} / ${slides.length} diapositivas',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Controles del operador · Flechas para avanzar o retroceder · B para ocultar',
          style: TextStyle(color: Colors.blueGrey, fontSize: 12),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, b) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EN PANTALLA',
                      style: TextStyle(fontSize: 10, letterSpacing: 2),
                    ),
                    const SizedBox(height: 8),
                    AspectRatio(
                      aspectRatio: aspect,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SlideView(
                              slide: currentSlide,
                              blackout: blackout,
                              theme: slideTheme,
                              showTitle: showTitle,
                              transparentBackground:
                                  videoBackgroundPath != null && !blackout,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (b.maxWidth > 850) ...[
                const SizedBox(width: 18),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SIGUIENTE',
                        style: TextStyle(fontSize: 10, letterSpacing: 2),
                      ),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: aspect,
                        child: SlideView(
                          slide:
                              slides.isNotEmpty &&
                                  slideIndex + 1 < slides.length
                              ? slides[slideIndex + 1]
                              : const SlideData('', 'Fin', ''),
                          theme: slideTheme,
                          showTitle: showTitle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: slideIndex > 0 ? () => move(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 20),
            Text(currentSlide.label),
            const SizedBox(width: 20),
            IconButton.filled(
              onPressed: slideIndex + 1 < slides.length ? () => move(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const Divider(height: 30),
        GlassSurface(
          radius: 20,
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 4 : 16,
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<int>(
                    value: slideTheme,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Azul CGID')),
                      DropdownMenuItem(value: 1, child: Text('Negro Puro')),
                      DropdownMenuItem(value: 2, child: Text('Claro / Cálido')),
                      DropdownMenuItem(
                        value: 3,
                        child: Text('Verde Esmeralda'),
                      ),
                      DropdownMenuItem(value: 4, child: Text('Borgoña / Vino')),
                      DropdownMenuItem(
                        value: 5,
                        child: Text('Azul Noche Profundo'),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => slideTheme = v!);
                      widget.prefs.setInt('slideTheme', slideTheme);
                      syncOutput();
                    },
                  ),
                  DropdownButton<double>(
                    value: aspect,
                    items: const [
                      DropdownMenuItem(value: 16 / 9, child: Text('16:9')),
                      DropdownMenuItem(value: 4 / 3, child: Text('4:3')),
                    ],
                    onChanged: (v) {
                      setState(() => aspect = v!);
                      if (presented != null) prepare(presented!);
                    },
                  ),
                  DropdownButton<int>(
                    value: lines,
                    items: [
                      for (final n in [2, 3, 4, 5, 6])
                        DropdownMenuItem(value: n, child: Text('$n líneas')),
                    ],
                    onChanged: (v) {
                      setState(() => lines = v!);
                      if (presented != null) prepare(presented!);
                    },
                  ),
                  if (videoBackgroundPath != null)
                    ActionChip(
                      avatar: const Icon(Icons.close, size: 16),
                      label: const Text('Quitar Fondo de Video'),
                      onPressed: () {
                        setState(() => videoBackgroundPath = null);
                        syncOutput();
                      },
                    )
                  else
                    ActionChip(
                      avatar: const Icon(Icons.video_library, size: 16),
                      label: const Text('Fondo de Video'),
                      onPressed: () async {
                        final file = await FilePicker.pickFile(
                          type: FileType.video,
                        );
                        if (file != null && file.path != null) {
                          setState(() {
                            videoBackgroundPath = file.path;
                          });
                          syncOutput();
                        }
                      },
                    ),
                  FilterChip(
                    label: const Text('Título'),
                    selected: showTitle,
                    onSelected: (v) {
                      setState(() => showTitle = v);
                      syncOutput();
                    },
                  ),
                  FilterChip(
                    label: const Text('Repetir coro'),
                    selected: repeatChorus,
                    onSelected: (v) {
                      setState(() => repeatChorus = v);
                      if (presented != null) prepare(presented!);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              marqueeControls(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < slides.length; i++)
              SizedBox(
                width: 190,
                child: Card(
                  color: i == slideIndex ? accentPanel : cardColor,
                  child: InkWell(
                    onTap: () {
                      setState(() => slideIndex = i);
                      syncOutput();
                      focus.requestFocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1} · ${slides[i].label}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (slides[i].mediaId != null)
                            AspectRatio(
                              aspectRatio: aspect,
                              child: SlideView(slide: slides[i]),
                            )
                          else
                            Text(
                              slides[i].text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (plan.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'Orden del culto',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          for (final e in plan)
            ListTile(
              title: Text(e.title),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => prepare(e),
            ),
        ],
      ],
    ),
  );

  Widget marqueeControls() => LayoutBuilder(
    builder: (context, constraints) {
      final field = Row(
        children: [
          const Icon(Icons.campaign, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: marqueeController,
              decoration: InputDecoration(
                hintText: 'Aviso (cintillo) en pantalla...',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    marqueeController.clear();
                    if (marqueeText != null) {
                      setState(() => marqueeText = null);
                      syncOutput();
                    }
                  },
                ),
              ),
              onSubmitted: (text) {
                setState(
                  () => marqueeText = text.trim().isEmpty ? null : text.trim(),
                );
                syncOutput();
              },
            ),
          ),
        ],
      );
      final button = FilledButton.icon(
        icon: Icon(
          marqueeText == null ? Icons.visibility : Icons.visibility_off,
        ),
        label: Text(marqueeText == null ? 'Mostrar' : 'Ocultar'),
        onPressed: () {
          setState(() {
            if (marqueeText == null) {
              final text = marqueeController.text.trim();
              if (text.isNotEmpty) marqueeText = text;
            } else {
              marqueeText = null;
            }
          });
          syncOutput();
        },
      );
      if (constraints.maxWidth < 500) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), button],
        );
      }
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 12),
          button,
        ],
      );
    },
  );

  Future<void> addServiceSection() async {
    var sectionType = 'Oración';
    final title = TextEditingController(text: sectionType);
    final body = TextEditingController();
    final notes = TextEditingController();
    final result = await showDialog<Entry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Agregar sección al culto'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: sectionType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final option in serviceSectionIcons.entries)
                        DropdownMenuItem(
                          value: option.key,
                          child: Row(
                            children: [
                              Icon(option.value, size: 20),
                              const SizedBox(width: 10),
                              Text(option.key),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      final previous = sectionType;
                      updateDialog(() => sectionType = value);
                      if (title.text.trim().isEmpty ||
                          title.text.trim() == previous) {
                        title.text = value;
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Título dentro del orden',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: body,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Texto o indicación visible (opcional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notas privadas para quien dirige (opcional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  Entry(
                    id: 'service-${DateTime.now().microsecondsSinceEpoch}',
                    title: title.text.trim(),
                    subtitle: 'Orden de culto · $sectionType',
                    sections: [Section(sectionType, body.text.trim())],
                    notes: notes.text.trim(),
                  ),
                );
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (result != null) addPlan(result);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    body.dispose();
    notes.dispose();
  }

  Future<void> addBibleToPlan() async {
    var results = <Entry>[];
    final entries = await showDialog<List<Entry>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Agregar cita bíblica'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Cita',
                    hintText: 'Juan 3:16-18',
                  ),
                  onChanged: (value) =>
                      update(() => results = lib.references(value)),
                ),
                const SizedBox(height: 12),
                Text(
                  results.isEmpty
                      ? 'Escribe libro, capítulo y versículos válidos.'
                      : results.map((e) => e.title).join('\n'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: results.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, results),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || entries == null) return;
    for (final entry in entries) {
      addPlan(entry);
    }
  }

  Future<void> addFaithToPlan() async {
    var filter = '';
    final entry = await showDialog<Entry>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Agregar punto de fe'),
          content: SizedBox(
            width: 480,
            height: 400,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar punto de fe',
                  ),
                  onChanged: (value) =>
                      update(() => filter = normalized(value)),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in lib.faith.where(
                        (e) => e.searchable.contains(filter),
                      ))
                        ListTile(
                          title: Text(entry.title),
                          onTap: () => Navigator.pop(dialogContext, entry),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (mounted && entry != null) addPlan(entry);
  }

  bool fileBusy = false;
  String fileProgress = '';
  Future<void> importCultFile() async {
    if (fileBusy) return;
    setState(() {
      fileBusy = true;
      fileProgress = 'Selecciona un archivo…';
    });
    try {
      final file = await cult_picker.pickCultFile(CultFiles.maxBytes);
      if (!mounted) return;
      if (file == null) {
        setState(() => fileProgress = 'Importación cancelada.');
        return;
      }
      final name = file.$1;
      var bytes = file.$2;
      if (name.toLowerCase().endsWith('.cgidpack')) {
        if (mounted) {
          setState(() => fileProgress = 'Descomprimiendo paquete .cgidpack…');
        }
        final pack = await CultFiles.importCgidPack(bytes);
        final importedName = pack['name'] as String;
        final importedEntries = pack['entries'] as List<Entry>;
        if (mounted) {
          setState(() {
            plan = importedEntries;
            planName.text = importedName;
            savePlan();
            fileProgress =
                'Culto "$importedName" importado con éxito (${importedEntries.length} elementos).';
          });
          message('Culto importado: $importedName');
        }
        return;
      }
      if (!name.toLowerCase().endsWith('.pdf')) {
        if (mounted) {
          setState(() => fileProgress = 'Convirtiendo PowerPoint localmente…');
        }
        bytes = await CultFiles.convert(
          bytes,
          name.toLowerCase().endsWith('.pptx') ? 'import-pptx' : 'import-ppt',
        );
      }
      final entry = await CultFiles.importPdf(
        bytes,
        name,
        progress: (value) {
          if (mounted) setState(() => fileProgress = value);
        },
      );
      if (mounted) {
        addPlan(entry);
        setState(
          () => fileProgress =
              'Importado: ${entry.title} (${entry.mediaIds.length} páginas).',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => fileProgress = 'No se importó el archivo: $error');
      }
      message('No se importó el archivo: $error');
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> exportCultFile(String format) async {
    if (fileBusy || plan.isEmpty) return;
    final entries = List<Entry>.of(plan);
    final name = planName.text.trim().replaceAll(
      RegExp(r'[^\w áéíóúÁÉÍÓÚñÑ-]'),
      '_',
    );
    setState(() {
      fileBusy = true;
      fileProgress = 'Preparando $format…';
    });
    try {
      if (format == 'cgidpack') {
        final packBytes = await CultFiles.exportCgidPack(name, entries);
        final saved = await cult_picker.saveCultFile(
          '${name.isEmpty ? 'Culto' : name}.cgidpack',
          packBytes,
          'application/octet-stream',
        );
        if (mounted) {
          setState(
            () => fileProgress = !saved
                ? 'Exportación cancelada.'
                : 'Paquete .cgidpack exportado con éxito.',
          );
        }
        return;
      }

      var bytes = await CultFiles.exportPdf(
        entries,
        lines: lines,
        aspect: aspect,
        repeatChorus: repeatChorus,
        theme: slideTheme,
        showTitle: showTitle,
      );
      if (format == 'pptx') {
        bytes = await CultFiles.convert(bytes, 'export-pptx');
      }
      final saved = await cult_picker.saveCultFile(
        '${name.isEmpty ? 'Culto' : name}.$format',
        bytes,
        format == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
      if (mounted) {
        setState(
          () => fileProgress = !saved
              ? 'Exportación cancelada.'
              : 'Exportación $format preparada.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => fileProgress = 'No se exportó el culto: $error');
      }
      message('No se exportó el culto: $error');
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> shareLiturgicalBulletin() async {
    if (plan.isEmpty) return;
    try {
      setState(() => fileBusy = true);
      final pdfBytes = await BulletinPdfGenerator.generateBulletin(planName.text.trim(), plan);
      await Printing.sharePdf(bytes: pdfBytes, filename: 'boletin_liturgico.pdf');
    } catch (e) {
      message('Error al generar boletín: $e');
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> editPlanItemNotes(int i) async {
    final controller = TextEditingController(text: plan[i].notes);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notas privadas: ${plan[i].title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estas notas se verán en el Teleprompter móvil y en la pantalla del predicador (Stage Display), NUNCA en el proyector.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Ej: Leer sólo estrofas 1 y 3. Dirige Hno. Carlos.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar Nota'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        plan[i] = plan[i].copyWith(notes: result);
      });
      savePlan();
      syncOutput();
    }
  }

  Future<void> persistServiceTemplates() async {
    final encoded = jsonEncode(
      serviceTemplates.map((template) => template.toJson()).toList(),
    );
    if (!await widget.prefs.setString('serviceTemplates', encoded)) {
      message('No se pudieron guardar las plantillas.');
    }
  }

  Future<(String, String)?> templateDetails({ServiceTemplate? template}) async {
    final controller = TextEditingController(text: template?.title ?? '');
    var selectedIcon = template?.iconKey ?? 'church';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: Text(
            template == null ? 'Nueva plantilla' : 'Editar plantilla',
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Título de la plantilla',
                    hintText: 'Ej. Orden del presidente',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Elige un icono',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in serviceTemplateIcons.entries)
                      ChoiceChip(
                        selected: selectedIcon == option.key,
                        avatar: Icon(option.value, size: 20),
                        label: Text(
                          serviceTemplateIconLabels[option.key] ?? option.key,
                        ),
                        onSelected: (_) =>
                            updateDialog(() => selectedIcon = option.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final title = controller.text.trim();
                if (title.isNotEmpty) {
                  Navigator.pop(dialogContext, (title, selectedIcon));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    controller.dispose();
    return result;
  }

  Future<void> createTemplateFromPlan() async {
    if (plan.isEmpty) {
      message('Agrega elementos al orden antes de crear una plantilla.');
      return;
    }
    final details = await templateDetails();
    if (details == null || !mounted) return;
    final template = ServiceTemplate(
      id: 'template-${DateTime.now().microsecondsSinceEpoch}',
      title: details.$1,
      iconKey: details.$2,
      entries: List<Entry>.of(plan),
    );
    setState(() => serviceTemplates.add(template));
    await persistServiceTemplates();
    message('Plantilla "${template.title}" creada.');
  }

  void loadServiceTemplate(ServiceTemplate template) {
    setState(() {
      plan = List<Entry>.of(template.entries);
      final now = DateTime.now();
      planName.text = '${template.title} (${now.day}/${now.month})';
    });
    savePlan();
    message(
      'Plantilla "${template.title}" cargada con ${template.entries.length} elementos.',
    );
  }

  Future<void> showTemplateManager() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Mis plantillas de culto'),
          content: SizedBox(
            width: 620,
            child: serviceTemplates.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Aún no tienes plantillas. Prepara un orden de culto y guárdalo como plantilla para reutilizarlo.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: serviceTemplates.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final template = serviceTemplates[index];
                      return ListTile(
                        leading: Icon(
                          serviceTemplateIcons[template.iconKey] ??
                              Icons.church_outlined,
                        ),
                        title: Text(template.title),
                        subtitle: Text(
                          '${template.entries.length} elementos · Toca para usar',
                        ),
                        onTap: () {
                          Navigator.pop(dialogContext);
                          loadServiceTemplate(template);
                        },
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Opciones de plantilla',
                          onSelected: (action) async {
                            if (action == 'edit') {
                              final details = await templateDetails(
                                template: template,
                              );
                              if (details != null && mounted) {
                                setState(() {
                                  serviceTemplates[index] = template.copyWith(
                                    title: details.$1,
                                    iconKey: details.$2,
                                  );
                                });
                                updateDialog(() {});
                                await persistServiceTemplates();
                              }
                            } else if (action == 'replace' && plan.isNotEmpty) {
                              setState(() {
                                serviceTemplates[index] = template.copyWith(
                                  entries: List<Entry>.of(plan),
                                );
                              });
                              updateDialog(() {});
                              await persistServiceTemplates();
                              message('Contenido de la plantilla actualizado.');
                            } else if (action == 'delete') {
                              setState(() => serviceTemplates.removeAt(index));
                              updateDialog(() {});
                              await persistServiceTemplates();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar título e icono'),
                            ),
                            PopupMenuItem(
                              value: 'replace',
                              enabled: plan.isNotEmpty,
                              child: const Text(
                                'Actualizar con el orden actual',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar plantilla'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: plan.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await createTemplateFromPlan();
                    },
              icon: const Icon(Icons.add),
              label: const Text('Guardar orden actual'),
            ),
          ],
        ),
      ),
    );
  }

  Widget servicePlan() => Padding(
    padding: const EdgeInsets.all(28),
    child: ListView(
      children: [
        const AmbientSectionHeader(
          icon: Icons.playlist_play,
          title: 'Prepara el próximo culto',
          subtitle: 'Combina himnos, pasajes, oraciones, avisos y mensajes. Arrastra para cambiar el orden.',
        ),
        const SizedBox(height: 20),
        GlassSurface(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: planName,
                enabled: !fileBusy,
                decoration: const InputDecoration(
                  labelText: 'Nombre del culto',
                ),
                onSubmitted: (_) {
                  setState(savePlan);
                  message('Culto guardado.');
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      setState(savePlan);
                      message('Culto guardado.');
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: addServiceSection,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Sección'),
                  ),
                  OutlinedButton(
                    onPressed: () => changeTab(1),
                    child: const Text('Agregar himnos'),
                  ),
                  OutlinedButton(
                    onPressed: addBibleToPlan,
                    child: const Text('Agregar cita bíblica'),
                  ),
                  OutlinedButton(
                    onPressed: addFaithToPlan,
                    child: const Text('Agregar punto de fe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: fileBusy ? null : showTemplateManager,
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: const Text('Plantillas'),
                  ),
                  OutlinedButton.icon(
                    onPressed: fileBusy ? null : importCultFile,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Importar archivo (.cgidpack / PDF)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: fileBusy || plan.isEmpty
                        ? null
                        : () => exportCultFile('cgidpack'),
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Exportar paquete (.cgidpack)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: fileBusy || plan.isEmpty
                        ? null
                        : shareLiturgicalBulletin,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Compartir Boletín PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent,
                      side: const BorderSide(color: Colors.blueAccent),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: fileBusy || plan.isEmpty
                        ? null
                        : () => exportCultFile('pdf'),
                    child: const Text('Exportar PDF'),
                  ),
                  OutlinedButton(
                    onPressed: fileBusy || plan.isEmpty
                        ? null
                        : () => exportCultFile('pptx'),
                    child: const Text('Exportar PowerPoint'),
                  ),
                  if (savedPlans.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'Abrir culto guardado',
                      enabled: !fileBusy,
                      onSelected: (name) {
                        setState(() {
                          activePlan = name;
                          planName.text = name;
                          plan = [
                            for (final e in savedPlans[name])
                              Entry.fromJson(Map<String, dynamic>.from(e)),
                          ];
                        });
                        persist('activePlan', name);
                      },
                      itemBuilder: (_) => [
                        for (final name in savedPlans.keys)
                          PopupMenuItem(value: name, child: Text(name)),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Abrir guardado ?'),
                      ),
                    ),
                  TextButton(
                    onPressed: fileBusy
                        ? null
                        : () {
                            setState(() {
                              plan = [];
                              planName.text =
                                  'Nuevo culto ${DateTime.now().day}-${DateTime.now().month}';
                            });
                          },
                    child: const Text('Nuevo culto'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (fileBusy) const LinearProgressIndicator(),
              if (fileProgress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(fileProgress),
                ),
              const Text(
                'Importación visual: conserva las páginas, sin animaciones ni videos. PowerPoint requiere el servidor local y Microsoft PowerPoint instalado.',
                style: TextStyle(fontSize: 12),
              ),
              const Text(
                'En la web local, las exportaciones también quedan en CGID/output/cultos.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        plan.isEmpty
            ? const Center(
                child: Text(
                  'Tu lista está lista para recibir el primer canto.',
                ),
              )
            : ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plan.length,
                onReorderItem: (a, b) {
                  setState(() {
                    final e = plan.removeAt(a);
                    plan.insert(b, e);
                  });
                  savePlan();
                },
                itemBuilder: (context, i) => Card(
                  key: ValueKey('plan-$i-${plan[i].id}'),
                  elevation: 0,
                  color: cardColor,
                  child: ListTile(
                    leading: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.blueGrey,
                      ),
                    ),
                    title: Text(plan[i].title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan[i].mediaIds.isEmpty
                              ? '${plan[i].sections.length} secciones'
                              : '${plan[i].mediaIds.length} páginas importadas',
                        ),
                        if (plan[i].notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.note_alt,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Nota privada: ${plan[i].notes}',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    onTap: () => prepare(plan[i]),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: plan[i].notes.isNotEmpty
                              ? 'Editar nota privada'
                              : 'Agregar nota privada',
                          icon: Icon(
                            plan[i].notes.isNotEmpty
                                ? Icons.note_alt
                                : Icons.note_alt_outlined,
                            color: plan[i].notes.isNotEmpty
                                ? Colors.amber
                                : Colors.blueGrey,
                          ),
                          onPressed: () => editPlanItemNotes(i),
                        ),
                        IconButton(
                          tooltip: 'Quitar de esta lista',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            setState(() => plan.removeAt(i));
                            savePlan();
                          },
                        ),
                        const SizedBox(width: 25),
                      ],
                    ),
                  ),
                ),
              ),
      ],
    ),
  );
  Widget downloads() {
    return FutureBuilder(
      future: http.get(
        Uri.parse(
          'https://api.github.com/repos/ecavazosdeanda-coder/CGID/releases/latest',
        ),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error al cargar descargas: ${snapshot.error}'),
          );
        }

        String version = 'Desconocida';
        List<dynamic> assets = [];
        try {
          if (snapshot.hasData && snapshot.data!.statusCode == 200) {
            final data = jsonDecode(snapshot.data!.body);
            version = data['tag_name'] ?? version;
            assets = data['assets'] ?? [];
          }
        } catch (_) {}

        Widget buildDownloadButton(String title, IconData icon, String url) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  if (url.isNotEmpty) launchUrl(Uri.parse(url));
                },
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              url.isNotEmpty
                                  ? 'Descargar la versión $version'
                                  : 'No disponible en este momento',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (url.isNotEmpty) const Icon(Icons.download, size: 32),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        String getAssetUrl(String extension) {
          for (var asset in assets) {
            if (asset['name'].toString().toLowerCase().endsWith(extension)) {
              return asset['browser_download_url'];
            }
          }
          return '';
        }

        return ListView(
          padding: const EdgeInsets.all(32),
          children: [
            const Text(
              'Descargar Aplicación',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Obtén la versión instalable para tu dispositivo. La biblioteca se incluye en la aplicación; los audios requieren conexión o descarga previa. Las funciones disponibles dependen de la plataforma.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            buildDownloadButton(
              'Windows (.exe)',
              Icons.window,
              getAssetUrl('.exe'),
            ),
            buildDownloadButton(
              'Android (.apk)',
              Icons.android,
              getAssetUrl('.apk'),
            ),
            buildDownloadButton(
              'macOS (.dmg)',
              Icons.apple,
              getAssetUrl('.dmg'),
            ),
            buildDownloadButton(
              'iPhone / iOS (.zip · sin firmar)',
              Icons.phone_iphone,
              getAssetUrl('_ios_sin_firmar.zip'),
            ),
            const Text(
              'iPhone / iOS: esta descarga es una compilación sin firmar. No se puede instalar directamente en un iPhone; requiere firma Apple antes de su instalación.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        );
      },
    );
  }

  void _showChurchSettings() {
    final nameController = TextEditingController(text: globalChurchName);
    String selectedLogo = globalChurchLogoAsset;
    String selectedSabbathLogo = globalChurchSabbathLogoAsset;

    Widget buildDropdown(
      String label,
      String value,
      void Function(String) onChanged,
      void Function(void Function()) setState,
    ) {
      final isCustom = value.startsWith('base64:');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: isCustom ? 'custom' : value,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(
                value: 'assets/branding/icon_silver_blue.png',
                child: Text('Icono Plata/Azul (Predeterminado)'),
              ),
              const DropdownMenuItem(
                value: 'assets/branding/icon_gold_blue.png',
                child: Text('Icono Dorado/Azul'),
              ),
              const DropdownMenuItem(
                value: 'assets/branding/logo.png',
                child: Text('Logotipo Completo'),
              ),
              const DropdownMenuItem(
                value: 'assets/branding/logodorado.png',
                child: Text('Logotipo Completo (Dorado)'),
              ),
              if (isCustom)
                const DropdownMenuItem(
                  value: 'custom',
                  child: Text('Logotipo personalizado (Subido)'),
                ),
            ],
            onChanged: (v) {
              if (v != null && v != 'custom') onChanged(v);
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Subir logotipo personalizado...'),
            onPressed: () async {
              final file = await FilePicker.pickFile(type: FileType.image);
              if (file != null) {
                final bytes = await file.readAsBytes();
                if (bytes != null) {
                  onChanged('base64:' + base64Encode(bytes));
                  setState(() {});
                }
              }
            },
          ),
          if (isCustom)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(value.substring(7)),
                  height: 80,
                  errorBuilder: (c, e, s) => const Text('Error de imagen'),
                ),
              ),
            ),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Personalizar Iglesia'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nombre de la congregación:'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'Ej. Iglesia de Dios - Misión Central',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    buildDropdown(
                      'Logotipo habitual (domingo a viernes):',
                      selectedLogo,
                      (v) => selectedLogo = v,
                      setState,
                    ),
                    const SizedBox(height: 24),
                    buildDropdown(
                      'Logotipo de sábado (incluye viernes de tarde):',
                      selectedSabbathLogo,
                      (v) => selectedSabbathLogo = v,
                      setState,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'El nombre y logotipo aparecerán automáticamente en la pantalla de proyección inactiva de acuerdo al día.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  globalChurchName = nameController.text.trim();
                  if (globalChurchName.isEmpty)
                    globalChurchName =
                        'Conferencia General de la Iglesia de Dios';
                  globalChurchLogoAsset = selectedLogo;
                  globalChurchSabbathLogoAsset = selectedSabbathLogo;

                  widget.prefs.setString('churchName', globalChurchName);
                  widget.prefs.setString(
                    'churchLogoAsset',
                    globalChurchLogoAsset,
                  );
                  widget.prefs.setString(
                    'churchSabbathLogoAsset',
                    globalChurchSabbathLogoAsset,
                  );

                  this.setState(() {});
                  syncOutput();
                  Navigator.pop(context);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget about() => ListView(
    padding: const EdgeInsets.all(32),
    children: [
      Center(
        child: Column(
          children: [
            const ChurchLogo(height: 112),
            const SizedBox(height: 16),
            Text(
              'CGID · Biblioteca y proyección',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('Versión 1.0 · Compilación 15'),
            const SizedBox(height: 4),
            Text(
              isSabbathBranding()
                  ? 'Identidad del sábado · emblema dorado'
                  : 'Identidad habitual · emblema azul',
              style: TextStyle(color: secondaryText),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      GlassSurface(
        radius: 20,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Acerca del sistema',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            /* Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Personalizar Iglesia'),
                onPressed: _showChurchSettings,
              ),
            ), */
            SizedBox(height: 10),
            Text(
              'CGID reúne la biblioteca congregacional, Biblia, himnario, puntos de fe, partituras, audio y herramientas de proyección en una aplicación multiplataforma. Está diseñado para preparar el orden del culto y apoyar al presidente, al predicador, a músicos y al equipo de proyección.',
              style: TextStyle(height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      GlassSurface(
        radius: 20,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Funciones principales',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Text(
              '• Proyección independiente y monitor de escenario.\n'
              '• Control remoto por red local y código QR.\n'
              '• Planes y plantillas de culto creados por cada usuario.\n'
              '• Notas privadas para presidencia y predicación.\n'
              '• Audio, lectura TTS, partituras y sincronización de letras.\n'
              '• Temporizador, cintillo, pantalla negra y fondos de video.\n'
              '• Importación y exportación de órdenes de culto.',
              style: TextStyle(height: 1.7),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      GlassSurface(
        radius: 20,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cómo proyectar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Text(
              '1. Conecta la segunda pantalla y extiende el escritorio.\n'
              '2. Prepara un canto, pasaje o elemento del culto.\n'
              '3. Abre Proyección o Monitor de escenario.\n'
              '4. Lleva la ventana a la pantalla correspondiente y usa F11.\n'
              '5. Controla las diapositivas desde el operador o el remoto local.',
              style: TextStyle(height: 1.7),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Fuentes y créditos',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      SelectableText(lib.notice, style: const TextStyle(height: 1.7)),
      const SizedBox(height: 12),
      const Text(
        'Las letras y los puntos de fe proceden de los documentos aportados. Las partituras digitales se obtienen mediante reconocimiento MusicXML y se publican después de revisión musical.',
      ),
      const SizedBox(height: 20),
      for (final w in lib.warnings.where(
        (w) => !w.toString().contains('Punto 32'),
      ))
        ListTile(leading: const Icon(Icons.info_outline), title: Text('$w')),
      const SizedBox(height: 20),
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'CGID · Biblioteca y proyección',
          applicationVersion: '1.0 (15)',
          applicationIcon: const ChurchLogo(height: 72),
        ),
        child: const Text('Licencias de componentes'),
      ),
      const SizedBox(height: 12),
      Text(
        'Sistema desarrollado por Eustolio Cavazos de Anda',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: secondaryText),
      ),
    ],
  );
}
