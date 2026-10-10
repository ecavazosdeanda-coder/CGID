import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/document_model.dart';
import '../services/literature_pdf_service.dart';
import '../../comments/reading_comments.dart';

class DocumentViewerScreen extends StatefulWidget {
  final DocumentModel document;
  final LiteraturePdfService? pdfService;

  const DocumentViewerScreen({
    super.key,
    required this.document,
    this.pdfService,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _controller = PdfViewerController();
  final _searchController = TextEditingController();
  PdfTextSearcher? _searcher;
  bool _showSearch = false;
  late final _pdfService = widget.pdfService ?? LiteraturePdfService();
  Uint8List? _bytes;
  bool _offline = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _cacheWarning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _searcher?.removeListener(_onSearchChanged);
    _searcher?.dispose();
    _searcher = null;
    setState(() {
      _showSearch = false;
      _loading = true;
      _error = null;
      _cacheWarning = null;
    });
    try {
      if (widget.document.assetPath?.isNotEmpty == true) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      Uint8List? cached;
      try {
        cached = await _pdfService.downloaded(widget.document);
      } catch (_) {
        _cacheWarning = 'No se pudo leer la copia local. Se intentará abrir online; vuelve a descargarla para usarla sin conexión.';
      }
      final bytes = cached ?? await _pdfService.fetch(widget.document);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _offline = cached != null;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveOffline() async {
    setState(() => _saving = true);
    try {
      await _pdfService.saveOffline(widget.document, _bytes!);
      if (mounted) {
        setState(() => _offline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guardado en la app para leer sin conexión.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar. Revisa el espacio disponible o los permisos de almacenamiento del navegador.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher?.removeListener(_onSearchChanged);
    _searcher?.dispose();
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
                onChanged: (text) => _searcher?.startTextSearch(text),
              )
            : Text(widget.document.title),
        actions: [
          ReadingCommentsButton(
            target: ReadingTarget(
              'literature',
              widget.document.id,
              widget.document.title,
            ),
            compact: true,
          ),
          if (_showSearch && _searcher?.hasMatches == true) ...[
            Center(
              child: Text(
                '${(_searcher!.currentIndex ?? 0) + 1}/${_searcher!.matches.length}',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _searcher?.goToPrevMatch,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _searcher?.goToNextMatch,
            ),
          ],
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            tooltip: _showSearch ? 'Cerrar búsqueda' : 'Buscar en el documento',
            onPressed: _searcher == null
                ? null
                : () {
                    setState(() => _showSearch = !_showSearch);
                    if (!_showSearch) {
                      _searchController.clear();
                      _searcher?.resetTextSearch();
                    }
                  },
          ),
          if (!kIsWeb && widget.document.url != null)
            IconButton(
              icon: Icon(_offline ? Icons.offline_pin : Icons.download),
              tooltip: _offline
                  ? 'Disponible sin conexión en esta app'
                  : 'Descargar para leer sin conexión',
              onPressed: _bytes == null || _saving || _offline
                  ? null
                  : _saveOffline,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_cacheWarning != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_cacheWarning!),
            ),
          Expanded(child: _buildPdfViewer(context)),
        ],
      ),
    );
  }

  Widget _buildPdfViewer(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    final document = widget.document;
    final hasAsset =
        document.assetPath != null && document.assetPath!.isNotEmpty;
    final hasUrl = document.url != null && document.url!.isNotEmpty;
    final params = PdfViewerParams(
      textSelectionParams: const PdfTextSelectionParams(enabled: !kIsWeb),
      // PdfTextSearcher requires a controller attached to a ready PdfViewer.
      // Constructing it in initState crashes before the back button is built.
      onViewerReady: (document, controller) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !controller.isReady || _searcher != null) return;
          final searcher = PdfTextSearcher(controller)
            ..addListener(_onSearchChanged);
          setState(() => _searcher = searcher);
        });
      },
      pagePaintCallbacks: [
        if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
      ],
    );

    if (hasAsset) {
      return PdfViewer.asset(
        document.assetPath!,
        controller: _controller,
        params: params,
      );
    } else if (hasUrl) {
      return PdfViewer.data(
        _bytes!,
        sourceName: document.id,
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
