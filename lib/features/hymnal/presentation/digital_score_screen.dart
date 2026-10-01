import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../content.dart';
import '../../../glass.dart';
import '../../../audio_handler.dart';
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
  final controller = PdfViewerController();

  Future<void> toggleFullScreen() async {
    final next = !fullScreen;
    setState(() => fullScreen = next);
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: fullScreen ? null : AppBar(title: Text(widget.hymn.title)),
    body: Stack(
      children: [
        Column(
          children: [
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
                          'Partitura digital OCRizada. Puedes hacer zoom.',
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
                        tooltip: 'Parte anterior',
                        onPressed: index == 0
                            ? null
                            : () {
                                setState(() => index--);
                                controller.goToPage(
                                  pageNumber: widget.scorePages[index],
                                );
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        'Parte ${index + 1} de ${widget.scorePages.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        tooltip: 'Parte siguiente',
                        onPressed: index == widget.scorePages.length - 1
                            ? null
                            : () {
                                setState(() => index++);
                                controller.goToPage(
                                  pageNumber: widget.scorePages[index],
                                );
                              },
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
  );
}
