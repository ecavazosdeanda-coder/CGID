import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../content.dart';
import '../services/score_catalog.dart';

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
  bool showPedalHelper = false;
  late int currentIndex;
  late Entry currentEntry;
  ChordChart? chordChart;
  bool chordLoading = false;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialRepertoireIndex;
    currentEntry = widget.entry;
    unawaited(_loadChordChart());
    unawaited(WakelockPlus.enable().catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _loadChordChart() async {
    final hymnId = currentEntry.id;
    setState(() {
      chordLoading = true;
      chordChart = null;
      showChords = false;
    });
    ChordChart? chart;
    try {
      chart = await scoreCatalog.chordChartFor(hymnId);
    } catch (_) {
      chart = null;
    }
    if (!mounted || currentEntry.id != hymnId) return;
    setState(() {
      chordChart = chart;
      chordLoading = false;
    });
  }

  @override
  void dispose() {
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

  String _transposeText(String text) {
    // Si los acordes están desactivados, eliminamos los corchetes de acordes [G], [Am], etc.
    if (!showChords) {
      return text.replaceAll(RegExp(r'\[[CDEFGAB][#b]?[^\]]*\]'), '');
    }

    return ChordTransposer.transposeText(
      text,
      transposeAmount,
      useSolfeo: useSolfeo,
    );
  }

  Widget _buildRichText(String text, Color textCol, Color chordCol) {
    final processed = _transposeText(text);

    // Si los acordes no están activados o no hay acordes en el texto, renderizado simple
    if (!showChords || !processed.contains('[')) {
      final cleanText = processed.replaceAll(RegExp(r'\[[^\]]+\]'), '');
      return Text(
        cleanText,
        style: TextStyle(
          color: textCol,
          fontSize: fontSize,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final lines = processed.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          _buildLyricLineWithChords(lines[i], textCol, chordCol),
          if (i < lines.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildLyricLineWithChords(String line, Color textCol, Color chordCol) {
    if (line.trim().isEmpty) return const SizedBox(height: 10);

    // Tokenizamos la línea palabra por palabra preservando acordes asociados
    final tokens = line.trim().split(RegExp(r'\s+'));
    return Wrap(
      spacing: 6.0,
      runSpacing: 10.0,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final token in tokens)
          _buildWordWithChord(token, textCol, chordCol),
      ],
    );
  }

  Widget _buildWordWithChord(String token, Color textCol, Color chordCol) {
    final chordRegex = RegExp(r'\[([^\]]+)\]');
    final chordMatches = chordRegex.allMatches(token);

    if (chordMatches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 22.0),
        child: Text(
          token,
          style: TextStyle(
            color: textCol,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final chordText = chordMatches.map((m) => m.group(1)!).join(' ');
    final cleanWord = token.replaceAll(chordRegex, '');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: chordCol.withAlpha(28),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: chordCol.withAlpha(100), width: 0.8),
          ),
          child: Text(
            chordText,
            style: TextStyle(
              color: chordCol,
              fontSize: (fontSize * 0.72).clamp(11.0, 24.0),
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Text(
          cleanWord.isEmpty ? ' ' : cleanWord,
          style: TextStyle(
            color: textCol,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    final displayedSections = showChords && chordChart != null
        ? chordChart!.applyToSections(currentEntry.sections)
        : currentEntry.sections;
    final hasChordChart = chordChart != null && chordChart!.isEmpty == false;

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

            // Transpose
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
              onPressed: chordLoading
                  ? null
                  : () {
                      if (!hasChordChart) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Esta partitura todavía no contiene acordes reconocibles.',
                            ),
                          ),
                        );
                        return;
                      }
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
              if (showChords && hasChordChart)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade900,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'Acordes extraídos de la partitura MusicXML${chordChart!.keyLabel.isEmpty ? '' : ' · Tono original: ${chordChart!.keyLabel}'}. Requieren revisión musical.',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
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
                    for (final section in displayedSections)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: dark
                                ? const Color(0xff233138)
                                : const Color(0xffe2d9c8),
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
                      ),
                  ],
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
