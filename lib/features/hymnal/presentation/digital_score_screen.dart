import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../content.dart';
import '../services/hymn_customization_service.dart';
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
  bool hasCustomScore = false;
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<User?>? _authSubscription;

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
    try {
      if (Firebase.apps.isNotEmpty) {
        _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {}
    _checkCustomScore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _checkCustomScore() async {
    final hasCustom = await hymnCustomizationService.hasCustomScore(widget.hymn.id);
    if (mounted && hasCustom != hasCustomScore) {
      setState(() => hasCustomScore = hasCustom);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
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

  Future<void> _downloadOfficialScore() async {
    final bytes = await hymnCustomizationService.getOfficialScoreBytes(widget.hymn.id);
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo encontrar el archivo oficial.')),
        );
      }
      return;
    }
    hymnCustomizationService.downloadFile(bytes, '${widget.hymn.id}_partitura.mxl');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Archivo descargado (.mxl). Ábrelo en MuseScore para afinar notas y compases.'),
        ),
      );
    }
  }

  Future<void> _uploadCustomScore() async {
    if (!HymnCustomizationService.isMasterAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'Acceso restringido: Solo el Administrador Maestro (ecavazosdeanda@gmail.com) puede subir partituras.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mxl', 'musicxml', 'xml'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ok = await hymnCustomizationService.saveCustomScore(
        hymnId: widget.hymn.id,
        bytes: bytes,
        fileName: file.name,
      );
      if (ok) {
        setState(() => hasCustomScore = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.teal,
              content: Text('¡Partitura corregida guardada y renderizada con éxito!'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('No se pudo procesar el archivo MusicXML.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir archivo: $e')),
        );
      }
    }
  }

  Future<void> _restoreOfficialScore() async {
    if (!HymnCustomizationService.isMasterAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'Acceso restringido: Solo el Administrador Maestro (ecavazosdeanda@gmail.com) puede restablecer partituras.',
            ),
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer partitura oficial'),
        content: const Text(
          '¿Deseas descartar tu partitura personalizada y volver a la versión oficial?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await hymnCustomizationService.clearCustomScore(widget.hymn.id);
    if (mounted) {
      setState(() => hasCustomScore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partitura restablecida a la oficial.')),
      );
    }
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
                  PopupMenuButton<String>(
                    tooltip: 'Opciones y corrección de partitura',
                    icon: Icon(
                      hasCustomScore ? Icons.check_circle : Icons.tune,
                      color: hasCustomScore ? Colors.tealAccent : null,
                    ),
                    onSelected: (value) {
                      if (value == 'download') _downloadOfficialScore();
                      if (value == 'upload') _uploadCustomScore();
                      if (value == 'restore') _restoreOfficialScore();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          leading: Icon(Icons.download),
                          title: Text('Descargar MusicXML (.mxl)'),
                          subtitle: Text('Para abrir y afinar en MuseScore'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      if (HymnCustomizationService.isMasterAdmin) ...[
                        const PopupMenuItem(
                          value: 'upload',
                          child: ListTile(
                            leading: Icon(Icons.upload_file),
                            title: Text('Subir partitura corregida'),
                            subtitle: Text('.mxl o .musicxml corregido'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (hasCustomScore)
                          const PopupMenuItem(
                            value: 'restore',
                            child: ListTile(
                              leading: Icon(Icons.restore, color: Colors.red),
                              title: Text('Restablecer oficial', style: TextStyle(color: Colors.red)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ],
                  ),
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
                    : (hasCustomScore
                        ? Colors.teal.shade800
                        : Theme.of(context).colorScheme.tertiaryContainer),
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
                            : (hasCustomScore
                                ? Icons.check_circle
                                : Icons.auto_awesome),
                        color: hasCustomScore ? Colors.white : null,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          showOriginal
                              ? 'Original escaneado: se muestra únicamente como referencia.'
                              : (hasCustomScore
                                  ? 'Partitura personalizada activa (corregida manualmente). Mostrando tu archivo.'
                                  : 'Partitura limpia reconstruida desde MusicXML. Verifica notas y ritmo antes de uso oficial.'),
                          style: TextStyle(
                            fontSize: 13,
                            color: hasCustomScore ? Colors.white : null,
                          ),
                        ),
                      ),
                      if (!showOriginal && HymnCustomizationService.isMasterAdmin)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: hasCustomScore ? Colors.white : null,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _uploadCustomScore,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: Text(
                            hasCustomScore ? 'Reemplazar' : 'Subir corregida',
                            style: const TextStyle(fontSize: 12),
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
                      customKey: hasCustomScore ? widget.hymn.id : null,
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
