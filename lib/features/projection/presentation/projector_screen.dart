import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projection_provider.dart';
import '../../../glass.dart';
import '../../../slide_view.dart';
import '../../../projection_native.dart'
    if (dart.library.js_interop) '../../../projection_web.dart'
    as projection;
import 'stream_overlay_dialog.dart';

class ProjectorScreen extends ConsumerWidget {
  const ProjectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectionProvider);
    final notifier = ref.read(projectionProvider.notifier);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.pageDown) {
          notifier.move(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.pageUp) {
          notifier.move(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyB) {
          notifier.toggleBlack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: GlassSurface(
                    radius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () =>
                              projection.openOutput(notifier.outputState),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Abrir Proyector'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              projection.openStage(notifier.outputState),
                          icon: const Icon(Icons.monitor),
                          label: const Text('Monitor de Escenario'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => StreamOverlayDialog.show(
                            context,
                            notifier.outputState,
                          ),
                          icon: const Icon(
                            Icons.sensors,
                            color: Color(0xFF6366F1),
                          ),
                          label: const Text('Salida OBS / Stream'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => notifier.toggleBlack(),
                          icon: Icon(
                            state.blackout
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          label: Text(
                            state.blackout ? 'Mostrar' : 'Ocultar (B)',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: state.blackout
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (state.presented != null)
              Expanded(
                child: GlassSurface(
                  radius: 20,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.presented!.title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 250,
                                childAspectRatio: 16 / 9,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                          itemCount: state.slides.length,
                          itemBuilder: (context, i) {
                            final isActive = i == state.slideIndex;
                            return InkWell(
                              onTap: () => notifier.setSlideIndex(i),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow: isActive
                                      ? [
                                          BoxShadow(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.4),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: IgnorePointer(
                                    child: SlideView(
                                      slide: state.slides[i],
                                      theme: state.slideTheme,
                                      showTitle: state.showTitle,
                                      transparentBackground: false,
                                      blackout: false,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.present_to_all,
                        size: 64,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nada en proyección',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      const Text(
                        'Selecciona un elemento del Constructor Litúrgico o la Biblioteca.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
