import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../content.dart';
import '../services/score_catalog.dart';
import 'digital_score_view.dart';

class DigitalScoreScreen extends StatefulWidget {
  final Entry hymn;
  final DigitalScoreInfo score;

  const DigitalScoreScreen({
    super.key,
    required this.hymn,
    required this.score,
  });

  @override
  State<DigitalScoreScreen> createState() => _DigitalScoreScreenState();
}

class _DigitalScoreScreenState extends State<DigitalScoreScreen> {
  int index = 0;
  bool fullScreen = false;
  bool showPedalNotice = false;
  bool showOriginal = false;
  final FocusNode _focusNode = FocusNode();

  Future<void> toggleFullScreen() async {
    final next = !fullScreen;
    setState(() => fullScreen = next);
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _nextPart() {
    if (index < widget.score.files.length - 1) setState(() => index++);
  }

  void _previousPart() {
    if (index > 0) setState(() => index--);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space) {
      _nextPart();
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _previousPart();
    }
  }

  int get _originalPage {
    if (widget.score.sourcePages.isEmpty) return 1;
    return widget.score.sourcePages[index.clamp(
      0,
      widget.score.sourcePages.length - 1,
    )];
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: fullScreen
            ? null
            : AppBar(
                title: Text(widget.hymn.title),
                actions: [
                  IconButton(
                    tooltip: 'Pedales Bluetooth (PageFlip/AirTurn)',
                    icon: const Icon(Icons.settings_remote_outlined),
                    onPressed: () =>
                        setState(() => showPedalNotice = !showPedalNotice),
                  ),
                  IconButton(
                    tooltip: 'Pantalla completa',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: toggleFullScreen,
                  ),
                ],
              ),
        body: Column(
          children: [
            if (!fullScreen && showPedalNotice)
              Material(
                color: Colors.amber.shade900,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.keyboard_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Usa el pedal, espacio o flechas para cambiar de parte.',
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
                            setState(() => showPedalNotice = false),
                      ),
                    ],
                  ),
                ),
              ),
            if (!fullScreen)
              Material(
                color: showOriginal
                    ? Theme.of(context).colorScheme.errorContainer
                    : Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        showOriginal
                            ? Icons.picture_as_pdf_outlined
                            : Icons.auto_awesome,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          showOriginal
                              ? 'Original escaneado: se muestra únicamente como referencia.'
                              : 'Partitura limpia reconstruida desde MusicXML. Verifica notas y ritmo antes de uso oficial.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!fullScreen && widget.score.files.length > 1)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Parte anterior',
                      onPressed: index == 0 ? null : _previousPart,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      'Parte ${index + 1} de ${widget.score.files.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      tooltip: 'Parte siguiente',
                      onPressed: index == widget.score.files.length - 1
                          ? null
                          : _nextPart,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: showOriginal
                  ? PdfViewer.asset(
                      'assets/pdfs/partituras_app.pdf',
                      key: ValueKey('original-$index-$_originalPage'),
                      initialPageNumber: _originalPage,
                      params: PdfViewerParams(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                    )
                  : buildDigitalScoreView(
                      widget.score.files[index],
                      dark: dark,
                    ),
            ),
          ],
        ),
        bottomNavigationBar: fullScreen
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => showOriginal = !showOriginal),
                    icon: Icon(
                      showOriginal
                          ? Icons.music_note
                          : Icons.picture_as_pdf_outlined,
                    ),
                    label: Text(
                      showOriginal
                          ? 'Volver a la partitura digital'
                          : 'Ver partitura original',
                    ),
                  ),
                ),
              ),
        floatingActionButton: fullScreen
            ? FloatingActionButton.small(
                onPressed: toggleFullScreen,
                child: const Icon(Icons.fullscreen_exit),
              )
            : null,
      ),
    );
  }
}

class OriginalScoreBookScreen extends StatelessWidget {
  const OriginalScoreBookScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Partituras originales')),
    body: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Documento escaneado de referencia. Para uso normal vuelve al catálogo y abre la partitura digital limpia.',
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PdfViewer.asset('assets/pdfs/partituras_app.pdf'),
        ),
      ],
    ),
  );
}
