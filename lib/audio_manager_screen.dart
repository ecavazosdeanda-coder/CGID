import 'dart:async';

import 'package:flutter/material.dart';

import 'audio_manager.dart';
import 'glass.dart';

class AudioManagerScreen extends StatefulWidget {
  final int totalCatalogAudios;

  const AudioManagerScreen({super.key, this.totalCatalogAudios = 316});

  @override
  State<AudioManagerScreen> createState() => _AudioManagerScreenState();
}

class _AudioManagerScreenState extends State<AudioManagerScreen> {
  final AudioManager _manager = AudioManager.instance;
  int _downloadedCount = 0;
  int _diskBytes = 0;
  bool _loading = true;
  StreamSubscription<AudioDownloadProgress>? _downloadSub;
  AudioDownloadProgress? _currentProgress;
  String _serverUrl = '';
  final TextEditingController _urlController = TextEditingController();
  bool _editingUrl = false;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshStats() async {
    setState(() => _loading = true);
    final count = await _manager.countDownloadedAudios();
    final bytes = await _manager.getDownloadedBytes();
    final url = await _manager.getServerUrl();

    if (mounted) {
      setState(() {
        _downloadedCount = count;
        _diskBytes = bytes;
        _serverUrl = url;
        _urlController.text = url;
        _loading = false;
      });
    }
  }

  void _startDownload() {
    if (_manager.isDownloading) return;
    setState(() {
      _currentProgress = AudioDownloadProgress(
        progress: 0.0,
        status: 'Iniciando descarga…',
      );
    });

    _downloadSub?.cancel();
    _downloadSub = _manager
        .downloadAudioZip(customUrl: _serverUrl)
        .listen(
          (progress) {
            if (mounted) {
              setState(() => _currentProgress = progress);
              if (progress.progress >= 1.0) {
                _refreshStats();
              }
            }
          },
          onError: (err) {
            if (mounted) {
              setState(() {
                _currentProgress = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error al descargar: $err'),
                  backgroundColor: Colors.red,
                ),
              );
              _refreshStats();
            }
          },
          onDone: () {
            if (mounted) {
              _refreshStats();
            }
          },
        );
  }

  void _cancelDownload() {
    _manager.cancelDownload();
    _downloadSub?.cancel();
    setState(() {
      _currentProgress = null;
    });
    _refreshStats();
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar audios descargados?'),
        content: const Text(
          'Se borrarán todos los audios locales para liberar espacio. Podrás descargarlos nuevamente cuando lo desees.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _manager.deleteDownloadedAudios();
      await _refreshStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audios eliminados correctamente.')),
        );
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1000) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = _manager.isDownloading;
    final total = widget.totalCatalogAudios;
    final percentInstalled = total > 0
        ? (_downloadedCount / total).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestor de Descarga de Audios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: isDownloading ? null : _refreshStats,
          ),
        ],
      ),
      body: AmbientBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AmbientSectionHeader(
                          icon: Icons.library_music_outlined,
                          title: 'Biblioteca de audio',
                          subtitle: 'Descarga los himnos para escucharlos sin conexión y administra el espacio local.',
                        ),
                        const SizedBox(height: 20),
                        // Tarjeta de estado
                        Card(
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _downloadedCount > 0
                                          ? Icons.cloud_done_outlined
                                          : Icons.cloud_download_outlined,
                                      size: 36,
                                      color: _downloadedCount > 0
                                          ? Colors.green
                                          : Colors.amber,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Himnos descargados localmente',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            '$_downloadedCount de $total disponibles (${(percentInstalled * 100).toStringAsFixed(0)}%)',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                LinearProgressIndicator(
                                  value: percentInstalled,
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Espacio en disco ocupado: ${_formatBytes(_diskBytes)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_downloadedCount > 0 && !isDownloading)
                                      TextButton.icon(
                                        onPressed: _confirmDelete,
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'Liberar espacio',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Panel de Descarga / Progreso
                        if (isDownloading && _currentProgress != null)
                          Card(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          _currentProgress!.status,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        tooltip: 'Cancelar',
                                        onPressed: _cancelDownload,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  LinearProgressIndicator(
                                    value: _currentProgress!.progress > 0
                                        ? _currentProgress!.progress
                                        : null,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _startDownload,
                            icon: const Icon(Icons.download),
                            label: Text(
                              _downloadedCount > 0
                                  ? 'Actualizar / Reinstalar paquete de audios'
                                  : 'Descargar paquete completo de audios (ZIP)',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),

                        const SizedBox(height: 30),

                        // Configuración del Servidor
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Servidor de descarga',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _editingUrl
                                            ? Icons.check
                                            : Icons.edit_outlined,
                                      ),
                                      tooltip: _editingUrl
                                          ? 'Guardar'
                                          : 'Modificar URL',
                                      onPressed: () async {
                                        if (_editingUrl) {
                                          final messenger =
                                              ScaffoldMessenger.of(context);
                                          await _manager.setServerUrl(
                                            _urlController.text.trim(),
                                          );
                                          if (!mounted) return;
                                          setState(() {
                                            _serverUrl = _urlController.text
                                                .trim();
                                            _editingUrl = false;
                                          });
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'URL de descarga actualizada.',
                                              ),
                                            ),
                                          );
                                        } else {
                                          setState(() => _editingUrl = true);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (_editingUrl)
                                  TextField(
                                    controller: _urlController,
                                    decoration: const InputDecoration(
                                      labelText: 'URL directa del archivo .ZIP',
                                      hintText: 'https://tudominio.com/audios_cgid.zip',
                                      border: OutlineInputBorder(),
                                    ),
                                  )
                                else
                                  Text(
                                    _serverUrl,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Nota: La aplicación admite cualquier URL directa HTTPS que aloje un archivo ZIP con los audios en formato MP3.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
