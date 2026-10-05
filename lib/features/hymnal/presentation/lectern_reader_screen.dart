import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../content.dart';
import '../services/hymn_customization_service.dart';
import '../services/score_catalog.dart';
import 'chord_lyrics_view.dart';
import 'hymn_chord_editor_dialog.dart';

class LecternReaderScreen extends StatefulWidget {
  final Entry entry;
  final List<Entry>? repertoireList;
  final int initialRepertoireIndex;

  const LecternReaderScreen({
    super.key,
    required this.entry,
    this.repertoireList,
    this.initialRepertoireIndex = 0,
  });

  @override
  State<LecternReaderScreen> createState() => _LecternReaderScreenState();
}

class _LecternReaderScreenState extends State<LecternReaderScreen> {
  double fontSize = 22.0;
  bool dark = true;
  int transposeAmount = 0;
  bool showChords = false;
  bool useSolfeo = false;
  bool preferFlats = false;
  bool showPedalHelper = false;
  int? userColumnsPreference;
  late int currentIndex;
  late Entry currentEntry;
  ChordChart? chordChart;
  List<Section>? customSections;
  bool chordLoading = false;
  StreamSubscription<User?>? _authSubscription;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialRepertoireIndex;
    currentEntry = widget.entry;
    try {
      if (Firebase.apps.isNotEmpty) {
        unawaited(HymnCustomizationService.refreshAdminStatus().then((_) {
          if (mounted) setState(() {});
        }));
        _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) async {
          await HymnCustomizationService.refreshAdminStatus();
          if (mounted) setState(() {});
        });
      }
    } catch (_) {}
    unawaited(_loadChordChart());
    unawaited(WakelockPlus.enable().catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _loadChordChart({bool keepShowChords = false}) async {
    final hymnId = currentEntry.id;
    setState(() {
      chordLoading = true;
      if (!keepShowChords) {
        chordChart = null;
        customSections = null;
        showChords = false;
      }
    });

    // 1. Cargar únicamente si el Administrador ha guardado y publicado acordes para este himno
    final custom = await hymnCustomizationService.getCustomChords(hymnId);
    if (!mounted || currentEntry.id != hymnId) return;

    if (custom != null && custom.isNotEmpty) {
      setState(() {
        customSections = custom;
        chordChart = null;
        chordLoading = false;
        showChords = true;
      });
    } else {
      setState(() {
        customSections = null;
        chordChart = null;
        chordLoading = false;
        showChords = false;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  void _nextHymn() {
    if (widget.repertoireList != null &&
        currentIndex < widget.repertoireList!.length - 1) {
      setState(() {
        currentIndex++;
        currentEntry = widget.repertoireList![currentIndex];
        transposeAmount = 0;
      });
      unawaited(_loadChordChart());
      _scrollController.jumpTo(0);
    } else {
      _pageScroll(1);
    }
  }

  void _previousHymn() {
    if (widget.repertoireList != null && currentIndex > 0) {
      setState(() {
        currentIndex--;
        currentEntry = widget.repertoireList![currentIndex];
        transposeAmount = 0;
      });
      unawaited(_loadChordChart());
      _scrollController.jumpTo(0);
    } else {
      _pageScroll(-1);
    }
  }

  void _pageScroll(int direction) {
    if (!_scrollController.hasClients) return;
    final current = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final delta = 280.0 * direction;
    final target = (current + delta).clamp(0.0, maxScroll);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    // Pedales Bluetooth habituales (PageFlip / AirTurn) emiten PageDown/PageUp,
    // Flecha Arriba/Abajo, Flecha Izq/Der, o Espacio.
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space) {
      _pageScroll(1);
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      _pageScroll(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _pageScroll(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _pageScroll(-1);
    } else if (key == LogicalKeyboardKey.bracketRight) {
      _nextHymn();
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      _previousHymn();
    }
  }

  Widget _buildRichText(String text, Color textCol, Color chordCol) {
    return ChordLyricsBlock(
      text: text,
      fontSize: fontSize,
      textCol: textCol,
      chordCol: chordCol,
      showChords: showChords,
      transposeAmount: transposeAmount,
      useSolfeo: useSolfeo,
      preferFlats: preferFlats,
    );
  }

  int _determineColumnCount(double width, int sectionCount) {
    if (userColumnsPreference != null && userColumnsPreference! > 0) {
      return userColumnsPreference!.clamp(1, sectionCount > 0 ? sectionCount : 1);
    }
    if (sectionCount <= 1) return 1;
    if (width >= 1200 && sectionCount >= 3) return 3;
    if (width >= 720 && sectionCount >= 2) return 2;
    return 1;
  }

  List<List<Section>> _partitionSections(List<Section> sections, int numCols) {
    if (sections.isEmpty || numCols <= 1) {
      return [sections];
    }
    final cols = List.generate(numCols, (_) => <Section>[]);
    if (sections.length <= numCols) {
      for (var i = 0; i < sections.length; i++) {
        cols[i].add(sections[i]);
      }
      return cols;
    }

    int sectionWeight(Section s) {
      final lineCount = s.text.split('\n').where((l) => l.trim().isNotEmpty).length;
      return lineCount + (s.label.isNotEmpty ? 2 : 0);
    }

    if (numCols == 2) {
      final totalWeight = sections.fold<int>(0, (sum, s) => sum + sectionWeight(s));
      var currentWeight = 0;
      var splitIdx = 1;
      var bestDiff = double.infinity;

      for (var i = 1; i < sections.length; i++) {
        currentWeight += sectionWeight(sections[i - 1]);
        final col2Weight = totalWeight - currentWeight;
        final diff = (currentWeight - col2Weight).abs().toDouble();
        if (diff < bestDiff) {
          bestDiff = diff;
          splitIdx = i;
        }
      }
      cols[0].addAll(sections.sublist(0, splitIdx));
      cols[1].addAll(sections.sublist(splitIdx));
      return cols;
    }

    // 3 columnas
    final totalWeight = sections.fold<int>(0, (sum, s) => sum + sectionWeight(s));
    final targetColWeight = totalWeight / 3.0;
    var currentWeight = 0;
    var colIdx = 0;

    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final w = sectionWeight(s);
      final remainingSections = sections.length - i;
      final remainingCols = numCols - colIdx;

      if (remainingSections <= remainingCols && colIdx < numCols - 1) {
        colIdx++;
        currentWeight = 0;
      } else if (colIdx < numCols - 1 &&
          currentWeight + (w / 2) > targetColWeight &&
          cols[colIdx].isNotEmpty) {
        colIdx++;
        currentWeight = 0;
      }
      cols[colIdx].add(s);
      currentWeight += w;
    }
    return cols;
  }

  Widget _buildSectionCard(
    Section section, {
    required Color cardBg,
    required Color labelCol,
    required Color textCol,
    required Color chordCol,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0xff233138) : const Color(0xffe2d9c8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                section.label.toUpperCase(),
                style: TextStyle(
                  color: labelCol,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSize * 0.55,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          _buildRichText(section.text, textCol, chordCol),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xff0b141a) : const Color(0xfffdfbf7);
    final textCol = dark ? Colors.white : const Color(0xff182229);
    final cardBg = dark ? const Color(0xff182229) : const Color(0xfff1ece1);
    final labelCol = dark ? const Color(0xff10b981) : const Color(0xff047857);
    final chordCol = dark ? Colors.amberAccent : Colors.deepOrange.shade800;

    final hasRepertoire =
        widget.repertoireList != null && widget.repertoireList!.isNotEmpty;
    final hasCustomChords =
        customSections != null && customSections!.isNotEmpty;
    final displayedSections = (showChords && hasCustomChords)
        ? customSections!
        : currentEntry.sections;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: dark
              ? const Color(0xff121d24)
              : const Color(0xffe8e2d5),
          foregroundColor: textCol,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentEntry.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (hasRepertoire)
                Text(
                  'Repertorio: Canto ${currentIndex + 1} de ${widget.repertoireList!.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: dark ? Colors.tealAccent : Colors.teal.shade900,
                  ),
                ),
            ],
          ),
          actions: [
            // Repertoire Navigation
            if (hasRepertoire) ...[
              IconButton(
                tooltip: 'Canto anterior del repertorio',
                icon: const Icon(Icons.skip_previous),
                onPressed: currentIndex > 0 ? _previousHymn : null,
              ),
              IconButton(
                tooltip: 'Siguiente canto del repertorio',
                icon: const Icon(Icons.skip_next),
                onPressed: currentIndex < widget.repertoireList!.length - 1
                    ? _nextHymn
                    : null,
              ),
              const VerticalDivider(width: 12, indent: 12, endIndent: 12),
            ],

            // Controles de Acordes y Transporte (Solo si este himno tiene acordes)
            if (hasCustomChords) ...[
              // Transpose -1
              IconButton(
                tooltip: 'Transportar Tono (-1 semitono)',
                icon: const Icon(Icons.exposure_minus_1),
                onPressed: showChords
                    ? () => setState(() => transposeAmount--)
                    : null,
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => transposeAmount = 0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Center(
                    child: Text(
                      transposeAmount > 0
                          ? '+$transposeAmount'
                          : '$transposeAmount',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: transposeAmount != 0 ? Colors.amber : null,
                      ),
                    ),
                  ),
                ),
              ),
              // Transpose +1
              IconButton(
                tooltip: 'Transportar Tono (+1 semitono)',
                icon: const Icon(Icons.exposure_plus_1),
                onPressed: showChords
                    ? () => setState(() => transposeAmount++)
                    : null,
              ),

              // Toggle Chords
              IconButton(
                tooltip: showChords ? 'Ocultar Acordes' : 'Mostrar Acordes',
                icon: Icon(
                  showChords ? Icons.music_note : Icons.music_off,
                  color: showChords ? chordCol : Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    showChords = !showChords;
                    if (!showChords) transposeAmount = 0;
                  });
                },
              ),

              // Toggle Notation (C, D, E vs Do, Re, Mi)
              if (showChords)
                Tooltip(
                  message: useSolfeo
                      ? 'Cambiar a cifrado americano (C, D, E)'
                      : 'Cambiar a solfeo latino (Do, Re, Mi)',
                  child: TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => setState(() => useSolfeo = !useSolfeo),
                    child: Text(
                      useSolfeo ? 'Do' : 'C',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: chordCol,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

              // Toggle Accidental notation (# sostenidos vs b bemoles)
              if (showChords)
                Tooltip(
                  message: preferFlats
                      ? 'Cambiar a sostenidos (#)'
                      : 'Cambiar a bemoles (b)',
                  child: TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => setState(() => preferFlats = !preferFlats),
                    child: Text(
                      preferFlats ? 'b' : '#',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: chordCol,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
            ],

            // Editar o Agregar Acordes (Exclusivo Administrador)
            if (HymnCustomizationService.isAdmin)
              IconButton(
                tooltip: hasCustomChords
                    ? 'Editar acordes (Admin)'
                    : 'Agregar acordes a este canto (Admin)',
                icon: Icon(
                  hasCustomChords ? Icons.edit_note : Icons.playlist_add,
                  color: hasCustomChords ? Colors.amberAccent : Colors.tealAccent,
                ),
                onPressed: () async {
                  final result = await HymnChordEditorDialog.show(
                    context,
                    hymn: currentEntry,
                    initialSections: hasCustomChords ? customSections! : currentEntry.sections,
                  );
                  if (result != null) {
                    await _loadChordChart(keepShowChords: true);
                  }
                },
              ),

            // Font Sizing
            IconButton(
              tooltip: 'Reducir letra',
              icon: const Icon(Icons.text_decrease),
              onPressed: fontSize > 14
                  ? () => setState(() => fontSize -= 2)
                  : null,
            ),
            IconButton(
              tooltip: 'Aumentar letra',
              icon: const Icon(Icons.text_increase),
              onPressed: fontSize < 42
                  ? () => setState(() => fontSize += 2)
                  : null,
            ),

            // Selector de Columnas (Atril apaisado / vertical)
            PopupMenuButton<int>(
              tooltip: 'Distribución de columnas (Atril)',
              icon: Icon(
                userColumnsPreference == 1
                    ? Icons.view_agenda_outlined
                    : (userColumnsPreference == 2
                        ? Icons.view_column_outlined
                        : (userColumnsPreference == 3
                            ? Icons.view_week_outlined
                            : Icons.auto_awesome_mosaic_outlined)),
              ),
              onSelected: (val) {
                setState(() {
                  userColumnsPreference = val == 0 ? null : val;
                });
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem<int>(
                  value: 0,
                  checked: userColumnsPreference == null,
                  child: const Text('Auto (adaptar a pantalla)'),
                ),
                CheckedPopupMenuItem<int>(
                  value: 1,
                  checked: userColumnsPreference == 1,
                  child: const Text('1 Columna (Vertical)'),
                ),
                CheckedPopupMenuItem<int>(
                  value: 2,
                  checked: userColumnsPreference == 2,
                  child: const Text('2 Columnas (Atril apaisado)'),
                ),
                CheckedPopupMenuItem<int>(
                  value: 3,
                  checked: userColumnsPreference == 3,
                  child: const Text('3 Columnas (Panorámico)'),
                ),
              ],
            ),

            // Bluetooth Pedal Helper Info
            IconButton(
              tooltip: 'Pedales Bluetooth (PageFlip/AirTurn)',
              icon: const Icon(Icons.keyboard_outlined),
              onPressed: () =>
                  setState(() => showPedalHelper = !showPedalHelper),
            ),

            // Light/Dark
            IconButton(
              tooltip: dark ? 'Modo claro' : 'Modo oscuro',
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => dark = !dark),
            ),
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xff153b45), Color(0xff0b141a)]
                  : const [Color(0xffe1eee8), Color(0xfffdfbf7)],
            ),
          ),
          child: Column(
            children: [
              if (showPedalHelper)
                Container(
                  color: Colors.amber.shade900,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.settings_remote,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Atril listo para pedales de pie Bluetooth (AirTurn, PageFlip) o teclas [AvPág]/[RePág] / flechas. Avanza y retrocede sin usar las manos.',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => showPedalHelper = false),
                      ),
                    ],
                  ),
                ),
              if (chordLoading) const LinearProgressIndicator(minHeight: 3),
              if (HymnCustomizationService.isAdmin) ...[
                if (hasCustomChords)
                  Container(
                    width: double.infinity,
                    color: Colors.teal.shade800,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Modo Administrador · Acordes personalizados activos para este himno.',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.teal.shade900,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Editar acordes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () async {
                            final result = await HymnChordEditorDialog.show(
                              context,
                              hymn: currentEntry,
                              initialSections: customSections ?? currentEntry.sections,
                            );
                            if (result != null) {
                              await _loadChordChart(keepShowChords: true);
                            }
                          },
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    color: dark ? const Color(0xff152e35) : const Color(0xffe6f4ea),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          color: dark ? Colors.tealAccent : Colors.teal.shade800,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Modo Administrador · Este canto aún no tiene acordes.',
                            style: TextStyle(
                              color: dark ? Colors.tealAccent : Colors.teal.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 15),
                          label: const Text(
                            'Agregar acordes',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () async {
                            final result = await HymnChordEditorDialog.show(
                              context,
                              hymn: currentEntry,
                              initialSections: currentEntry.sections,
                            );
                            if (result != null) {
                              await _loadChordChart(keepShowChords: true);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final numCols = _determineColumnCount(
                      constraints.maxWidth,
                      displayedSections.length,
                    );
                    final partitioned = _partitionSections(displayedSections, numCols);

                    return SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth > 900 ? 32 : 16,
                        vertical: 20,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: numCols == 1
                                ? 850
                                : (numCols == 2 ? 1440 : 1880),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (currentEntry.subtitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    currentEntry.subtitle,
                                    style: TextStyle(
                                      color: dark
                                          ? const Color(0xff94a3b8)
                                          : const Color(0xff64748b),
                                      fontSize: fontSize * 0.7,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (numCols == 1)
                                for (final section in displayedSections)
                                  _buildSectionCard(
                                    section,
                                    cardBg: cardBg,
                                    labelCol: labelCol,
                                    textCol: textCol,
                                    chordCol: chordCol,
                                  )
                              else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var c = 0; c < partitioned.length; c++) ...[
                                      if (c > 0) const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            for (final section in partitioned[c])
                                              _buildSectionCard(
                                                section,
                                                cardBg: cardBg,
                                                labelCol: labelCol,
                                                textCol: textCol,
                                                chordCol: chordCol,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: hasRepertoire
            ? BottomAppBar(
                color: dark ? const Color(0xff121d24) : const Color(0xffe8e2d5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: currentIndex > 0 ? _previousHymn : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Anterior'),
                    ),
                    Text(
                      'Repertorio: ${currentIndex + 1} de ${widget.repertoireList!.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          currentIndex < widget.repertoireList!.length - 1
                          ? _nextHymn
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Siguiente'),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}
