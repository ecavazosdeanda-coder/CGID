import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'projection_native.dart'
    if (dart.library.js_interop) 'projection_web.dart'
    as projection;
import 'content.dart';
import 'countdown.dart';

class StageDisplayScreen extends StatefulWidget {
  const StageDisplayScreen({super.key});
  @override
  State<StageDisplayScreen> createState() => _StageDisplayScreenState();
}

class _StageDisplayScreenState extends State<StageDisplayScreen> {
  Map<String, dynamic> state = {};
  bool full = false;
  late Timer _clockTimer;
  late final void Function() _stopListening;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _stopListening = projection.listenOutput((s) {
      if (mounted) setState(() => state = s);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _stopListening();
    _clockTimer.cancel();
    super.dispose();
  }

  Future<void> fullscreen(bool value) async {
    try {
      await projection.fullScreen(value);
      full = value;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final current = state['slide'] != null
        ? SlideData.fromJson(Map<String, dynamic>.from(state['slide']))
        : null;
    final next = state['nextSlide'] != null
        ? SlideData.fromJson(Map<String, dynamic>.from(state['nextSlide']))
        : null;
    final blackout = state['blackout'] ?? false;

    final timeStr =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.f11) {
            fullscreen(!full);
            return KeyEventResult.handled;
          }
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            fullscreen(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onDoubleTap: () => fullscreen(!full),
          child: CountdownOverlay(
            endsAt: state['countdownEndsAt'] as int?,
            child: Container(
              color: blackout ? Colors.black : const Color(0xFF111111),
              padding: const EdgeInsets.all(24),
              child: blackout
                  ? const Center(
                      child: Text(
                        'PANTALLA NEGRA',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                current?.title ?? 'CGID',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            child: Text(
                              current?.text ?? 'Bienvenidos',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 56,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white24,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withValues(alpha: 0.05),
                            ),
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'SIGUIENTE',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 20,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  next?.text ?? 'Fin de la presentación',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
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
