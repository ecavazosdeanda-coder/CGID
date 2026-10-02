import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../content.dart';

class DigitalScoreScreen extends StatefulWidget {
  final Entry hymn;
  final List<int> scorePages;

  const DigitalScoreScreen({
    super.key,
    required this.hymn,
    required this.scorePages,
  });

  @override
  State<DigitalScoreScreen> createState() => _DigitalScoreScreenState();
}

class _DigitalScoreScreenState extends State<DigitalScoreScreen> {
  int index = 0;
  bool fullScreen = false;
  bool showPedalNotice = false;
  final controller = PdfViewerController();
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

  void _nextPage() {
    if (index < widget.scorePages.length - 1) {
      setState(() => index++);
      controller.goToPage(pageNumber: widget.scorePages[index]);
    }
  }

  void _previousPage() {
    if (index > 0) {
      setState(() => index--);
      controller.goToPage(pageNumber: widget.scorePages[index]);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    // Soporte para pedales Bluetooth (PageFlip / AirTurn)
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _previousPage();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () {
                      setState(() => showPedalNotice = !showPedalNotice);
                    },
                  ),
                  IconButton(
                    tooltip: fullScreen ? 'Salir de pantalla completa' : 'Pantalla completa',
                    icon: Icon(fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
                    onPressed: toggleFullScreen,
                  ),
                ],
              ),
        body: Stack(
          children: [
            Column(
              children: [
                if (!fullScreen && showPedalNotice)
                  Material(
                    color: Colors.amber.shade900,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.keyboard_outlined, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Pedales Bluetooth listos: Puedes cambiar de página pisando tu pedal AirTurn/PageFlip o usando flechas de teclado.',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 18),
                            onPressed: () => setState(() => showPedalNotice = false),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!fullScreen)
                  Material(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 18),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Partitura digital en alta resolución. Puedes hacer zoom y pasar página con pedales de pie.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!fullScreen && widget.scorePages.length > 1)
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Parte anterior (Pedal Izq / AvPág)',
                            onPressed: index == 0 ? null : _previousPage,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            'Parte ${index + 1} de ${widget.scorePages.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          IconButton(
                            tooltip: 'Parte siguiente (Pedal Der / RePág)',
                            onPressed: index == widget.scorePages.length - 1
                                ? null
                                : _nextPage,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: PdfViewer.asset(
                    'assets/pdfs/partituras_app.pdf',
                    controller: controller,
                    initialPageNumber: widget.scorePages.first,
                    params: PdfViewerParams(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                onPressed: toggleFullScreen,
                child: Icon(fullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
