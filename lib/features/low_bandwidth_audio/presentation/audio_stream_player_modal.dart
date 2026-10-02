import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tenant/models/church_model.dart';
import '../../tenant/providers/tenant_provider.dart';
import '../providers/low_bandwidth_audio_provider.dart';

class AudioStreamPlayerModal extends ConsumerStatefulWidget {
  final ChurchModel church;

  const AudioStreamPlayerModal({
    super.key,
    required this.church,
  });

  static Future<void> show(BuildContext context, ChurchModel church) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AudioStreamPlayerModal(church: church),
    );
  }

  @override
  ConsumerState<AudioStreamPlayerModal> createState() => _AudioStreamPlayerModalState();
}

class _AudioStreamPlayerModalState extends ConsumerState<AudioStreamPlayerModal> {
  late TextEditingController _urlController;
  bool _isEditingUrl = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.church.audioStreamUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final hours = d.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final streamState = ref.watch(lowBandwidthAudioProvider);
    final streamNotifier = ref.read(lowBandwidthAudioProvider.notifier);
    final effectiveStreamUrl = widget.church.audioStreamUrl.trim();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.radio, color: Colors.teal, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Modo Solo Audio (Bajo Ancho de Banda)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.church.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Data Saver Banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.data_saver_on, color: Colors.teal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ahorro extremo de datos móviles: Transmisión optimizada (~15-20 MB por servicio completo de 2 horas).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Visualizer & Status Area
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: streamState.isPlaying
                      ? [const Color(0xff183e43), const Color(0xff2d5f66)]
                      : [Colors.grey.shade800, Colors.grey.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    streamState.isPlaying
                        ? Icons.graphic_eq
                        : (streamState.isConnecting
                            ? Icons.hourglass_top
                            : Icons.sensors_off),
                    size: 48,
                    color: streamState.isPlaying ? Colors.tealAccent : Colors.white70,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    streamState.isPlaying
                        ? 'En Vivo: Señal de Audio Conectada'
                        : (streamState.isConnecting
                            ? 'Conectando con la señal...'
                            : (streamState.status == AudioStreamStatus.paused
                                ? 'En pausa'
                                : 'Listo para reproducir')),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (streamState.isPlaying) ...[
                    Text(
                      'Tiempo escuchado: ${_formatDuration(streamState.elapsed)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Datos estimados usados: ~${streamState.estimatedDataUsageMb.toStringAsFixed(2)} MB',
                      style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (streamState.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      streamState.errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (streamState.isPlaying)
                  IconButton.filledTonal(
                    iconSize: 32,
                    icon: const Icon(Icons.pause),
                    tooltip: 'Pausar',
                    onPressed: () => streamNotifier.pause(),
                  )
                else if (streamState.status == AudioStreamStatus.paused)
                  IconButton.filled(
                    iconSize: 36,
                    style: IconButton.styleFrom(backgroundColor: const Color(0xff183e43)),
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    tooltip: 'Reanudar',
                    onPressed: () => streamNotifier.resume(),
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff183e43),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: streamState.isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      streamState.isConnecting ? 'Conectando...' : 'Escuchar Culto',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: streamState.isConnecting
                        ? null
                        : () {
                            final targetUrl = _urlController.text.trim().isNotEmpty
                                ? _urlController.text.trim()
                                : effectiveStreamUrl;
                            streamNotifier.playStream(
                              targetUrl,
                              title: 'Culto en Vivo - ${widget.church.name}',
                            );
                          },
                  ),
                if (streamState.isPlaying || streamState.status == AudioStreamStatus.paused) ...[
                  const SizedBox(width: 16),
                  IconButton.outlined(
                    iconSize: 28,
                    icon: const Icon(Icons.stop),
                    tooltip: 'Detener',
                    onPressed: () => streamNotifier.stop(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            // Volume Slider
            Row(
              children: [
                const Icon(Icons.volume_down, size: 20, color: Colors.grey),
                Expanded(
                  child: Slider(
                    value: streamState.volume,
                    activeColor: Colors.teal,
                    onChanged: (val) => streamNotifier.setVolume(val),
                  ),
                ),
                const Icon(Icons.volume_up, size: 20, color: Colors.grey),
              ],
            ),
            const Divider(),

            // Custom Stream URL Option
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Enlace de la señal:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _isEditingUrl = !_isEditingUrl);
                  },
                  icon: Icon(_isEditingUrl ? Icons.check : Icons.edit, size: 14),
                  label: Text(_isEditingUrl ? 'Cerrar' : 'Personalizar URL', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (_isEditingUrl) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'URL de transmisión (Icecast, Shoutcast, Radio)',
                  hintText: 'https://stream.zeno.fm/xyz o http://radio.cgdi.org/live',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save, size: 18),
                    tooltip: 'Guardar para esta iglesia',
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                        'custom_audio_stream_${widget.church.id}',
                        _urlController.text.trim(),
                      );
                      ref.invalidate(tenantProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.teal,
                            content: Text('URL de transmisión guardada para esta iglesia.'),
                          ),
                        );
                        setState(() => _isEditingUrl = false);
                      }
                    },
                  ),
                ),
              ),
            ] else ...[
              Text(
                effectiveStreamUrl.isNotEmpty
                    ? effectiveStreamUrl
                    : 'Sin URL configurada (Usa el botón Personalizar)',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
