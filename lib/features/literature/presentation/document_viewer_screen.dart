import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/document_model.dart';

class DocumentViewerScreen extends StatefulWidget {
  final DocumentModel document;

  const DocumentViewerScreen({super.key, required this.document});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _controller = PdfViewerController();
  final _searchController = TextEditingController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller);
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _searcher.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher.removeListener(_onSearchChanged);
    _searcher.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar dentro del documento',
                  border: InputBorder.none,
                ),
                onChanged: _searcher.startTextSearch,
              )
            : Text(widget.document.title),
        actions: [
          if (_showSearch && _searcher.hasMatches) ...[
            Center(
              child: Text(
                '${(_searcher.currentIndex ?? 0) + 1}/${_searcher.matches.length}',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _searcher.goToPrevMatch,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _searcher.goToNextMatch,
            ),
          ],
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            tooltip: _showSearch ? 'Cerrar búsqueda' : 'Buscar en el documento',
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchController.clear();
                _searcher.resetTextSearch();
              }
            },
          ),
          if (widget.document.url != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Abrir o descargar documento original',
              onPressed: () async {
                final uri = Uri.tryParse(widget.document.url ?? '');
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: _buildPdfViewer(context),
    );
  }

  Widget _buildPdfViewer(BuildContext context) {
    final document = widget.document;
    final hasAsset =
        document.assetPath != null && document.assetPath!.isNotEmpty;
    final hasUrl = document.url != null && document.url!.isNotEmpty;
    final params = PdfViewerParams(
      pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
    );

    if (hasAsset) {
      return PdfViewer.asset(
        document.assetPath!,
        controller: _controller,
        params: params,
      );
    } else if (hasUrl) {
      return PdfViewer.uri(
        Uri.parse(document.url!),
        controller: _controller,
        params: params,
      );
    }

    return const Center(
      child: Text(
        'Documento no disponible (no hay archivo PDF ni URL vinculada).',
      ),
    );
  }
}
