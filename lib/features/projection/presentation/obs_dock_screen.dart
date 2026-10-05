import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../content.dart';
import '../providers/projection_provider.dart';
import '../services/obs_client.dart';

class ObsDockScreen extends ConsumerStatefulWidget {
  const ObsDockScreen({super.key});

  @override
  ConsumerState<ObsDockScreen> createState() => _ObsDockScreenState();
}

class _ObsDockScreenState extends ConsumerState<ObsDockScreen> {
  final TextEditingController _tickerController = TextEditingController();
  bool _isTickerActive = false;

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  void _sendAction(String action, [dynamic value]) {
    // Attempt local state sync or broadcast
    final notifier = ref.read(projectionProvider.notifier);
    if (action == 'next') {
      notifier.move(1);
    } else if (action == 'prev') {
      notifier.move(-1);
    } else if (action == 'toggleBlack') {
      notifier.toggleBlack();
    } else if (action == 'setTicker') {
      final text = value as String? ?? '';
      notifier.setMarquee(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(projectionProvider.select((s) => s.marqueeText), (prev, next) {
      if (next.isNotEmpty) {
        setState(() {
          _isTickerActive = true;
          _tickerController.text = next;
        });
      }
    });
    
    final state = ref.watch(projectionProvider);
    final blackout = state.blackout;
    final slide = ref.read(projectionProvider.notifier).currentSlide;
    
    final nextSlide = (state.slides.isNotEmpty && state.slideIndex + 1 < state.slides.length)
        ? state.slides[state.slideIndex + 1]
        : null;

    final obsClient = ref.watch(obsClientProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF18181B), // OBS Dark Studio UI theme
      body: SafeArea(
        child: Column(
          children: [
            // OBS Dock Header Bar
            _buildDockHeader(blackout, obsClient),
            const Divider(height: 1, color: Color(0xFF27272A)),

            // Main Dock Body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Program (Current Live Slide)
                  _buildProgramCard(slide, blackout),
                  const SizedBox(height: 12),

                  // Preview (Next Slide)
                  if (nextSlide != null) ...[
                    _buildPreviewCard(nextSlide),
                    const SizedBox(height: 12),
                  ],

                  // Quick Navigation Controls
                  _buildNavigationControls(blackout),
                  const SizedBox(height: 16),

                  // OBS WebSocket Status & Controls (If connected)
                  _buildObsStatusCard(obsClient),
                  const SizedBox(height: 16),

                  // Live Stream Ticker / Cintillo de Avisos
                  _buildStreamTickerCard(),
                  const SizedBox(height: 16),

                  // Quick Copy Lower Third URL
                  _buildQuickUrlCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDockHeader(bool blackout, ObsClient obsClient) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFF09090B),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: blackout
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            blackout ? 'LETRAS OCULTAS' : 'SINCRONIZADO EN VIVO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: blackout
                  ? const Color(0xFFF87171)
                  : const Color(0xFF34D399),
            ),
          ),
          const Spacer(),
          // Blackout panic button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: blackout
                  ? const Color(0xFF10B981)
                  : const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 32),
            ),
            icon: Icon(
              blackout ? Icons.visibility : Icons.visibility_off,
              size: 15,
            ),
            label: Text(
              blackout ? 'Mostrar Letra' : 'Ocultar Letra (B)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: () => _sendAction('toggleBlack'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramCard(SlideData? slide, bool blackout) {
    final hasText = slide != null &&
        slide.text.trim().isNotEmpty &&
        slide.text.trim() != 'Esperando contenido' &&
        !blackout;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasText
              ? const Color(0xFF38BDF8).withValues(alpha: 0.5)
              : Colors.white10,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasText
                      ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: hasText
                          ? const Color(0xFFEF4444)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'PROGRAM (EN VIVO)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: hasText
                            ? const Color(0xFFFCA5A5)
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (slide != null && slide.label.isNotEmpty)
                Text(
                  slide.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF38BDF8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (slide != null && slide.title.isNotEmpty)
            Text(
              slide.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            blackout
                ? 'Salida en pantalla negra (Sin letras en OBS)'
                : hasText
                    ? slide.text.trim()
                    : 'Esperando que el proyeccionista inicie un himno o versículo...',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: blackout
                  ? Colors.white38
                  : hasText
                      ? Colors.white
                      : Colors.white54,
              fontStyle: hasText ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(SlideData nextSlide) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'PREVIEW (SIGUIENTE):',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                nextSlide.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            nextSlide.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationControls(bool blackout) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Anterior (◀)'),
            onPressed: () => _sendAction('prev'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Siguiente (▶)'),
            onPressed: () => _sendAction('next'),
          ),
        ),
      ],
    );
  }

  Widget _buildObsStatusCard(ObsClient obsClient) {
    return ValueListenableBuilder<ObsState>(
      valueListenable: obsClient.stateNotifier,
      builder: (context, obsState, _) {
        if (!obsState.isConnected) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.sensors_off, size: 20, color: Colors.white38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OBS WebSocket v5',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        obsState.isConnecting
                            ? 'Conectando...'
                            : 'No conectado a ws://localhost:4455',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => obsClient.connect(),
                  child: const Text('Conectar'),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'OBS STUDIO V5 CONECTADO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF34D399),
                    ),
                  ),
                  const Spacer(),
                  if (obsState.isStreaming)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'LIVE ${obsState.streamTimecode}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // Controls row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: obsState.isRecording
                            ? const Color(0xFFF87171)
                            : Colors.white,
                        side: BorderSide(
                          color: obsState.isRecording
                              ? const Color(0xFFEF4444)
                              : Colors.white24,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: Icon(
                        obsState.isRecording
                            ? Icons.stop_circle
                            : Icons.fiber_manual_record,
                        size: 16,
                        color: obsState.isRecording
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFEF4444),
                      ),
                      label: Text(
                        obsState.isRecording ? 'Detener Grab.' : 'Grabar Culto',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => obsClient.toggleRecord(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (obsState.scenes.isNotEmpty)
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: obsState.currentScene.isNotEmpty
                              ? obsState.currentScene
                              : null,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                          hint: const Text(
                            'Escena OBS',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          items: obsState.scenes.map((s) {
                            return DropdownMenuItem(value: s, child: Text(s));
                          }).toList(),
                          onChanged: (sc) {
                            if (sc != null) obsClient.setCurrentScene(sc);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStreamTickerCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF27272A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign, size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              const Text(
                'Cintillo de Transmisión (Aviso en Vivo):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (_isTickerActive)
                TextButton(
                  onPressed: () {
                    _tickerController.clear();
                    setState(() => _isTickerActive = false);
                    _sendAction('setTicker', '');
                  },
                  child: const Text(
                    'Borrar',
                    style: TextStyle(color: Color(0xFFF87171), fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tickerController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Ej: Diezmos y ofrendas: Bancomer...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF18181B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                ),
                onPressed: () {
                  final text = _tickerController.text.trim();
                  setState(() => _isTickerActive = text.isNotEmpty);
                  _sendAction('setTicker', text);
                },
                child: const Text(
                  'Activar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickUrlCard() {
    final overlayUrl = Uri.base.replace(
      queryParameters: {'overlay': '1', 'mode': 'lowerthird', 'bg': 'transparent'},
      fragment: '',
    ).toString();

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white12),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      icon: const Icon(Icons.copy, size: 15),
      label: const Text(
        'Copiar Enlace Tercio Inferior (Browser Source)',
        style: TextStyle(fontSize: 11),
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: overlayUrl));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enlace para OBS Browser Source copiado.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
