import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tts_utils.dart';

import 'audio_manager.dart';
import 'audio_manager_screen.dart';
import 'content.dart';
import 'glass.dart';
import 'audio_handler.dart';

final playbackControllerProvider = Provider((ref) {
  final controller = PlaybackController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

// One controller per workspace: a hymn and a reading never overlap.
class PlaybackController extends ChangeNotifier {
  FlutterTts? _tts;
  AudioPlayer? _player;
  StreamSubscription<void>? _completed;
  StreamSubscription<Duration>? _positionUpdates, _durationUpdates;
  // Shared clock for lyric highlighting and the timing editor.
  Duration position = Duration.zero, duration = Duration.zero;
  bool _disposed = false;
  int _generation = 0;
  String? activeId, error;
  String? completedHymnId;
  bool playing = false;
  bool isShuffle = false;
  double speed = 1;
  double volume = 1.0;
  final Map<String, String> tracks = {};

  CgidAudioHandler? audioHandler;
  ({String title, String subtitle})? Function(String id)? titleLookup;

  void attachAudioHandler(CgidAudioHandler handler) {
    audioHandler = handler;
    handler.onPlayCallback = () async {
      if (activeId != null) {
        await resumeHymn();
      } else if (completedHymnId != null) {
        await playHymn(completedHymnId!);
      } else if (sortedHymnIds.isNotEmpty) {
        await playHymn(sortedHymnIds.first);
      }
    };
    handler.onPauseCallback = pauseHymn;
    handler.onStopCallback = stop;
    handler.onNextCallback = () => nextHymn();
    handler.onPreviousCallback = () => previousHymn();
    handler.onSeekCallback = seekHymn;
    handler.onSetSpeedCallback = setSpeed;
  }

  void _syncMediaItem(String id, [Duration? totalDur]) {
    if (audioHandler == null) return;
    final meta = titleLookup?.call(id);
    final title = meta?.title ?? 'Himno ${id.replaceAll(RegExp(r'\D'), '')}';
    final subtitle = meta?.subtitle;
    audioHandler!.updateItem(
      id: id,
      title: title,
      subtitle: subtitle,
      hymnDuration: totalDur ?? (duration > Duration.zero ? duration : null),
    );
  }

  void _syncPlaybackState() {
    audioHandler?.updateState(
      isPlaying: playing,
      currentPosition: position,
      totalDuration: duration,
    );
  }

  bool continuousPlayback = true;
  Timer? _sleepTimer;
  DateTime? sleepTimerEndsAt;
  void Function(String hymnId)? onHymnChanged;

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      sleepTimerEndsAt = null;
    } else {
      sleepTimerEndsAt = DateTime.now().add(Duration(minutes: minutes));
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        stop();
        sleepTimerEndsAt = null;
        changed();
      });
    }
    changed();
  }

  Future<void> setSpeed(double newSpeed) async {
    speed = newSpeed;
    if (activeId != null && activeId!.startsWith('h')) {
      await _player?.setPlaybackRate(speed);
    } else if (activeId != null) {
      // En web la tasa del Web Speech API usa 1.0 como velocidad normal.
      // Actualizarla aquí permite que el selector afecte también la lectura
      // TTS (y no solamente las pistas de audio).
      await _tts?.setSpeechRate(ttsSpeechRate(speed, isWeb: kIsWeb));
    }
    changed();
  }

  Future<void> setVolume(double newVolume) async {
    volume = newVolume;
    await _player?.setVolume(volume);
    await _tts?.setVolume(volume);
    changed();
  }

  List<String> get sortedHymnIds {
    final ids = tracks.keys.where((k) => k.startsWith('h')).toList();
    ids.sort((a, b) {
      final numStrA = RegExp(r'\d+').firstMatch(a)?.group(0) ?? '0';
      final numStrB = RegExp(r'\d+').firstMatch(b)?.group(0) ?? '0';
      final numA = int.tryParse(numStrA) ?? 0;
      final numB = int.tryParse(numStrB) ?? 0;
      return numA.compareTo(numB);
    });
    return ids;
  }

  void toggleContinuous() {
    continuousPlayback = !continuousPlayback;
    changed();
  }

  void toggleShuffle() {
    isShuffle = !isShuffle;
    changed();
  }

  Future<void> nextHymn([String? fromId]) async {
    final currentId = fromId ?? activeId ?? completedHymnId;
    if (currentId == null || !currentId.startsWith('h')) return;
    final ids = sortedHymnIds;
    if (ids.isEmpty) return;
    
    if (isShuffle) {
      ids.shuffle();
      final randomId = ids.firstWhere((id) => id != currentId, orElse: () => currentId);
      await playHymn(randomId);
      return;
    }

    final idx = ids.indexOf(currentId);
    if (idx >= 0 && idx < ids.length - 1) {
      await playHymn(ids[idx + 1]);
    }
  }

  Future<void> previousHymn([String? fromId]) async {
    final currentId = fromId ?? activeId ?? completedHymnId;
    if (currentId == null || !currentId.startsWith('h')) return;
    final ids = sortedHymnIds;
    if (ids.isEmpty) return;

    if (isShuffle) {
      ids.shuffle();
      final randomId = ids.firstWhere((id) => id != currentId, orElse: () => currentId);
      await playHymn(randomId);
      return;
    }

    final idx = ids.indexOf(currentId);
    if (idx > 0) {
      await playHymn(ids[idx - 1]);
    }
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pauseHymn() async {
    if (activeId == null || !tracks.containsKey(activeId)) return;
    await _player?.pause();
    playing = false;
    changed();
    _syncPlaybackState();
  }

  Future<void> resumeHymn() async {
    if (activeId == null || !tracks.containsKey(activeId)) return;
    await _player?.resume();
    playing = true;
    changed();
    _syncPlaybackState();
  }

  Future<void> seekHymn(Duration value) async {
    if (activeId == null || !tracks.containsKey(activeId)) return;
    await _player?.seek(value);
    position = value;
    changed();
    _syncPlaybackState();
  }

  Future<void> loadTracks() async {
    if (tracks.isNotEmpty) return;
    try {
      final data = jsonDecode(
        await rootBundle.loadString('assets/audio/catalog_v2.json'),
      ) as Map<String, dynamic>;
      for (final entry in data.entries) {
        if (entry.value is String &&
            (entry.value as String).startsWith('audio/')) {
          tracks[entry.key] = entry.value;
        }
      }
      changed();
    } catch (_) {
      error = 'No se pudo cargar el catálogo de audio.';
      changed();
    }
  }

  Future<void> stop() async {
    _generation++;
    playing = false;
    activeId = null;
    completedHymnId = null;
    position = Duration.zero;
    duration = Duration.zero;
    changed();
    audioHandler?.resetState();
    try {
      await _tts?.stop();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> speak(String id, String text) async {
    final stopping = stop();
    final token = _generation;
    await stopping;
    if (_disposed || token != _generation || text.trim().isEmpty) return;
    // Pre‑procesar texto para que las citas bíblicas se lean correctamente.
    final processedText = preprocessBiblicalCitations(text);
    activeId = id;
    playing = true;
    error = null;
    onHymnChanged?.call(id);
    changed();
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setVolume(volume);
      tts.setErrorHandler((message) {
        if (token == _generation) {
          error = 'No se pudo reproducir la lectura. Comprueba las voces en español de tu dispositivo.';
          playing = false;
          changed();
        }
      });
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // First try to ensure the Google TTS engine (which has complete Spanish models) is selected
        try {
          final engines = await tts.getEngines;
          final preferredEngine = engines?.firstWhere(
            (e) =>
                e.toString().toLowerCase().contains('google') &&
                e.toString().toLowerCase().contains('tts'),
            orElse: () => null,
          );
          if (preferredEngine != null) {
            await tts.setEngine(preferredEngine.toString());
          }
        } catch (_) {}
        await configureAndroidSpeech(tts).timeout(const Duration(seconds: 15));
      } else {
        if (await tts.isLanguageAvailable('es-MX') == true) {
          await tts.setLanguage('es-MX');
        } else if (await tts.isLanguageAvailable('es-ES') == true) {
          await tts.setLanguage('es-ES');
        } else {
          await tts.setLanguage('es');
        }
      }

      await tts.setSpeechRate(ttsSpeechRate(speed, isWeb: kIsWeb));
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);
      for (final chunk in speechChunks(
        processedText,
        limit: kIsWeb ? 160 : 420,
      )) {
        if (_disposed || token != _generation || !playing) break;
        // El navegador crea una nueva locución para cada fragmento. Aplicar
        // la tasa de nuevo hace efectivos los cambios realizados durante una
        // lectura larga a partir del siguiente fragmento.
        await tts.setSpeechRate(ttsSpeechRate(speed, isWeb: kIsWeb));
        final result = await tts
            .speak(chunk, focus: true)
            .timeout(const Duration(seconds: 90));
        if (result == 0 && token == _generation) {
          throw StateError('El motor de voz rechazó la lectura.');
        }
      }
    } catch (exception) {
      debugPrint('CGID lectura: $exception');
      if (token == _generation) {
        error = exception is TimeoutException
            ? 'El motor de voz no respondió. Revisa la voz española en Ajustes → Texto a voz y vuelve a intentarlo.'
            : 'No se pudo iniciar la lectura: $exception';
        await _tts?.stop();
      }
    } finally {
      if (!_disposed && token == _generation) {
        playing = false;
        activeId = null;
        changed();
      }
    }
  }

  Future<void> playHymn(String id) async {
    final track = tracks[id];
    if (track == null) return;
    final stopping = stop();
    final token = _generation;
    await stopping;
    if (_disposed || token != _generation) return;
    activeId = id;
    playing = true;
    error = null;
    onHymnChanged?.call(id);
    changed();
    _syncMediaItem(id);
    _syncPlaybackState();
    try {
      if (_player == null) {
        _player = AudioPlayer();
        await _player!.setVolume(volume);
        _positionUpdates = _player!.onPositionChanged.listen((value) {
          position = value;
          changed();
          _syncPlaybackState();
        });
        _durationUpdates = _player!.onDurationChanged.listen((value) {
          duration = value;
          changed();
          if (activeId != null) {
            _syncMediaItem(activeId!, duration);
          }
          _syncPlaybackState();
        });
        _completed = _player!.onPlayerComplete.listen((_) {
          completedHymnId = activeId;
          position = duration;
          if (continuousPlayback &&
              activeId != null &&
              activeId!.startsWith('h')) {
            nextHymn();
          } else {
            playing = false;
            activeId = null;
            changed();
            audioHandler?.resetState();
          }
        });
      }
      final localFile = await AudioManager.instance.getLocalAudioFile(track);
      if (localFile != null) {
        await _player!.play(DeviceFileSource(localFile.path));
        await _player!.setPlaybackRate(speed);
        _syncPlaybackState();
      } else {
        try {
          await _player!.play(AssetSource(track));
          await _player!.setPlaybackRate(speed);
          _syncPlaybackState();
        } catch (_) {
          if (token == _generation) {
            // Streaming directo desde Internet Archive (Fallback principal)
            final fileName = track.replaceFirst('audio/', ''); // h1.mp3
            final archiveUrl =
                'https://archive.org/download/cantos-cgid/$fileName';

            error = kIsWeb
                ? 'Cargando audio...'
                : 'Conectando al servidor en línea...';
            changed();

            try {
              await _player!.play(UrlSource(archiveUrl));
              await _player!.setPlaybackRate(speed);
              error = null;
              changed();
              _syncPlaybackState();
              return;
            } catch (e) {
              if (token == _generation) {
                playing = false;
                activeId = null;
                error = 'Audio no disponible o sin conexión a internet.';
                changed();
                audioHandler?.resetState();
              }
            }
          }
          return;
        }
      }
    } catch (_) {
      if (token == _generation) {
        playing = false;
        activeId = null;
        error = 'No se pudo abrir el audio de este himno.';
        changed();
        audioHandler?.resetState();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tts?.stop().catchError((_) {
      return null;
    });
    _completed?.cancel();
    _positionUpdates?.cancel();
    _durationUpdates?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

List<Map<String, String>> spanishVoices(dynamic raw) {
  if (raw is! List) return [];
  final voices = raw
      .whereType<Map>()
      .where((voice) {
        final locale = '${voice['locale']}'.toLowerCase().replaceAll('_', '-');
        return (locale == 'es' || locale.startsWith('es-')) &&
            voice['name'] != null &&
            !'${voice['features']}'.contains('notInstalled');
      })
      .map(
        (voice) => {
          for (final key in ['name', 'locale', 'network_required'])
            key: '${voice[key] ?? ''}',
        },
      )
      .toList();
  int priority(Map<String, String> voice) =>
      (['1', 'true'].contains(voice['network_required']) ? 10 : 0) +
      (voice['locale']!.toLowerCase().replaceAll('_', '-') == 'es-mx' ? 0 : 1);
  voices.sort((a, b) => priority(a).compareTo(priority(b)));
  return voices;
}

Future<void> configureAndroidSpeech(FlutterTts tts) async {
  final voices = spanishVoices(await tts.getVoices);
  for (final voice in voices) {
    if (await tts.setLanguage(voice['locale']!) != 1) continue;
    if (await tts.setVoice({
          'name': voice['name']!,
          'locale': voice['locale']!,
        }) !=
        1) {
      continue;
    }
    await tts.setQueueMode(0);
    return;
  }
  // Some engines do not enumerate voices but can still provide a language.
  for (final locale in ['es-MX', 'es-ES', 'es-US', 'es']) {
    if (await tts.isLanguageAvailable(locale) == true &&
        await tts.setLanguage(locale) == 1) {
      await tts.setQueueMode(0);
      return;
    }
  }
  throw StateError('Instala una voz en español en Ajustes → Texto a voz.');
}

List<String> speechChunks(String text, {int limit = 420}) {
  final chunks = <String>[];
  var current = '';
  for (final word in text.trim().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (current.isNotEmpty && current.length + word.length + 1 > limit) {
      chunks.add(current);
      current = '';
    }
    current = current.isEmpty ? word : '$current $word';
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

class PlaybackControls extends StatelessWidget {
  final PlaybackController controller;
  final String contentId, text;
  final bool hymn;
  const PlaybackControls({
    super.key,
    required this.controller,
    required this.contentId,
    this.text = '',
    this.hymn = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final isThisActive = controller.activeId == contentId;
      final isPlayingThis = controller.playing && isThisActive;
      final available = !hymn || controller.tracks.containsKey(contentId);

      if (!hymn) {
        final active = controller.playing && controller.activeId == contentId;
        return GlassSurface(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: active
                        ? controller.stop
                        : () => controller.speak(contentId, text),
                    icon: Icon(
                      active
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                    ),
                    label: Text(active ? 'Detener lectura' : 'Escuchar texto'),
                  ),
                  DropdownButton<double>(
                    value: controller.speed,
                    items: [
                      for (final speed in [0.75, 0.9, 1.0, 1.1, 1.25, 1.5])
                        DropdownMenuItem(
                          value: speed,
                          child: Text('Voz ${speed}x'),
                        ),
                    ],
                    onChanged: (v) => controller.setSpeed(v!),
                  ),
                  if (active)
                    const Text(
                      'Leyendo con voz del sistema…',
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
        );
      }

      final durMs = isThisActive ? controller.duration.inMilliseconds : 0;
      final posMs = isThisActive ? controller.position.inMilliseconds : 0;
      final hasError = isThisActive && controller.error != null;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GlassSurface(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 28,
                    tooltip: 'Himno anterior',
                    onPressed: () => controller.previousHymn(contentId),
                  ),
                  IconButton(
                    icon: Icon(
                      isPlayingThis
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    iconSize: 46,
                    color: available
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                    tooltip: isPlayingThis
                        ? 'Pausar'
                        : isThisActive
                        ? 'Reanudar'
                        : 'Reproducir audio',
                    onPressed: !available
                        ? null
                        : () {
                            if (isPlayingThis) {
                              controller.pauseHymn();
                            } else if (isThisActive) {
                              controller.resumeHymn();
                            } else {
                              controller.playHymn(contentId);
                            }
                          },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 28,
                    tooltip: 'Himno siguiente',
                    onPressed: () => controller.nextHymn(contentId),
                  ),
                  IconButton(
                    icon: Icon(
                      controller.continuousPlayback
                          ? Icons.repeat
                          : Icons.repeat_one,
                      color: controller.continuousPlayback
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: controller.continuousPlayback
                        ? 'Modo: Continuo (pasa automáticamente al siguiente himno)'
                        : 'Modo: Repetir (repite este mismo himno)',
                    onPressed: controller.toggleContinuous,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: controller.isShuffle
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Aleatorio',
                    onPressed: controller.toggleShuffle,
                  ),
                  PopupMenuButton<double>(
                    initialValue: controller.speed,
                    tooltip: 'Velocidad (${controller.speed}x)',
                    icon: const Icon(Icons.speed),
                    onSelected: controller.setSpeed,
                    itemBuilder: (context) => [
                      for (final s in [0.75, 0.9, 1.0, 1.1, 1.25, 1.5])
                        PopupMenuItem(value: s, child: Text('Velocidad ${s}x')),
                    ],
                  ),
                  PopupMenuButton<int>(
                    tooltip: controller.sleepTimerEndsAt != null
                        ? 'Apagar a las ${controller.sleepTimerEndsAt!.hour.toString().padLeft(2, '0')}:${controller.sleepTimerEndsAt!.minute.toString().padLeft(2, '0')}'
                        : 'Temporizador de apagado',
                    icon: Icon(
                      Icons.bedtime,
                      color: controller.sleepTimerEndsAt != null
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onSelected: controller.setSleepTimer,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 0,
                        child: Text('Desactivar temporizador'),
                      ),
                      const PopupMenuItem(
                        value: 15,
                        child: Text('Apagar en 15 minutos'),
                      ),
                      const PopupMenuItem(
                        value: 30,
                        child: Text('Apagar en 30 minutos'),
                      ),
                      const PopupMenuItem(
                        value: 45,
                        child: Text('Apagar en 45 minutos'),
                      ),
                      const PopupMenuItem(
                        value: 60,
                        child: Text('Apagar en 60 minutos'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    formatDuration(
                      isThisActive ? controller.position : Duration.zero,
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 3,
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: durMs > 0
                            ? posMs.toDouble().clamp(0.0, durMs.toDouble())
                            : 0.0,
                        max: durMs > 0 ? durMs.toDouble() : 1.0,
                        onChanged: isThisActive && durMs > 0
                            ? (value) => controller.seekHymn(
                                Duration(milliseconds: value.round()),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    durMs > 0 ? formatDuration(controller.duration) : '--:--',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (!available)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Audio pendiente de incorporar en el catálogo.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              if (hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (controller.error!.contains('Gestor de Audios'))
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AudioManagerScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text(
                            'Ir al Gestor',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return "$minutes:$seconds";
}

class GlobalBottomPlayer extends StatelessWidget {
  final PlaybackController controller;
  final Library lib;
  final void Function(Entry entry)? onOpenHymn;

  const GlobalBottomPlayer({
    super.key,
    required this.controller,
    required this.lib,
    this.onOpenHymn,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.playing &&
            controller.activeId == null &&
            controller.position.inMilliseconds == 0) {
          return const SizedBox.shrink();
        }

        final activeId = controller.activeId ?? controller.completedHymnId;
        if (activeId == null || !activeId.startsWith('h')) {
          return const SizedBox.shrink();
        }

        final entry = lib.hymns.where((e) => e.id == activeId).firstOrNull;
        if (entry == null) return const SizedBox.shrink();

        final isPlaying = controller.playing;
        final hasError = controller.error != null;

        return Material(
          color: Colors.transparent,
          child: GlassSurface(
            radius: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 650;

                final titleAndTime = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasError)
                      Text(
                        controller.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (controller.duration.inMilliseconds > 0)
                      Row(
                        children: [
                          Text(
                            "${formatDuration(controller.position)} / ${formatDuration(controller.duration)}",
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SliderTheme(
                              data: const SliderThemeData(
                                trackHeight: 2,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                              ),
                              child: Slider(
                                value: controller.position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0,
                                      controller.duration.inMilliseconds
                                          .toDouble(),
                                    ),
                                max: controller.duration.inMilliseconds
                                    .toDouble(),
                                onChanged: (value) => controller.seekHymn(
                                  Duration(milliseconds: value.round()),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      const Text('Cargando...', style: TextStyle(fontSize: 11)),
                  ],
                );

                final playButton = IconButton(
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  iconSize: isCompact ? 36 : 40,
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () {
                    if (isPlaying) {
                      controller.pauseHymn();
                    } else if (controller.activeId != null) {
                      controller.resumeHymn();
                    } else if (controller.completedHymnId != null) {
                      controller.playHymn(controller.completedHymnId!);
                    }
                  },
                );

                if (isCompact) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => onOpenHymn?.call(entry),
                            child: titleAndTime,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: controller.previousHymn,
                        ),
                        playButton,
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: controller.nextHymn,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onSelected: (val) {
                            if (val == 'continuous') {
                              controller.toggleContinuous();
                            } else if (val.startsWith('speed_')) {
                              controller.setSpeed(
                                double.parse(val.substring(6)),
                              );
                            } else if (val.startsWith('timer_')) {
                              controller.setSleepTimer(
                                int.parse(val.substring(6)),
                              );
                            } else if (val == 'stop') {
                              controller.stop();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'continuous',
                              child: Row(
                                children: [
                                  Icon(
                                    controller.continuousPlayback
                                        ? Icons.repeat
                                        : Icons.repeat_one,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    controller.continuousPlayback
                                        ? 'Modo: Continuo (Cambiar)'
                                        : 'Modo: Repetir 1 (Cambiar)',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              enabled: false,
                              child: Text(
                                'Velocidad actual: ${controller.speed}x',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final s in [0.75, 0.9, 1.0, 1.1, 1.25])
                              PopupMenuItem(
                                value: 'speed_$s',
                                child: Text('Velocidad ${s}x'),
                              ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              enabled: false,
                              child: Text(
                                controller.sleepTimerEndsAt != null
                                    ? 'Apagado programado'
                                    : 'Temporizador de apagado',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'timer_0',
                              child: Text('Desactivar temporizador'),
                            ),
                            const PopupMenuItem(
                              value: 'timer_15',
                              child: Text('Apagar en 15 min'),
                            ),
                            const PopupMenuItem(
                              value: 'timer_30',
                              child: Text('Apagar en 30 min'),
                            ),
                            const PopupMenuItem(
                              value: 'timer_45',
                              child: Text('Apagar en 45 min'),
                            ),
                            const PopupMenuItem(
                              value: 'timer_60',
                              child: Text('Apagar en 60 min'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'stop',
                              child: Row(
                                children: [
                                  Icon(Icons.stop, color: Colors.red, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Detener audio',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => onOpenHymn?.call(entry),
                          child: titleAndTime,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        onPressed: controller.previousHymn,
                      ),
                      playButton,
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: controller.nextHymn,
                      ),
                      PopupMenuButton<double>(
                        initialValue: controller.speed,
                        tooltip: 'Velocidad (${controller.speed}x)',
                        icon: const Icon(Icons.speed),
                        onSelected: controller.setSpeed,
                        itemBuilder: (context) => [
                          for (final s in [0.75, 0.9, 1.0, 1.1, 1.25])
                            PopupMenuItem(value: s, child: Text('${s}x')),
                        ],
                      ),
                      PopupMenuButton<int>(
                        tooltip: controller.sleepTimerEndsAt != null
                            ? 'Apagar a las ${controller.sleepTimerEndsAt!.hour.toString().padLeft(2, '0')}:${controller.sleepTimerEndsAt!.minute.toString().padLeft(2, '0')}'
                            : 'Temporizador',
                        icon: Icon(
                          Icons.bedtime,
                          color: controller.sleepTimerEndsAt != null
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onSelected: controller.setSleepTimer,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 0,
                            child: Text('Desactivar'),
                          ),
                          const PopupMenuItem(
                            value: 15,
                            child: Text('15 minutos'),
                          ),
                          const PopupMenuItem(
                            value: 30,
                            child: Text('30 minutos'),
                          ),
                          const PopupMenuItem(
                            value: 45,
                            child: Text('45 minutos'),
                          ),
                          const PopupMenuItem(
                            value: 60,
                            child: Text('60 minutos'),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(
                          controller.continuousPlayback
                              ? Icons.repeat
                              : Icons.repeat_one,
                          color: controller.continuousPlayback
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: controller.continuousPlayback
                            ? 'Reproducción continua'
                            : 'Repetir uno',
                        onPressed: controller.toggleContinuous,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.shuffle,
                          color: controller.isShuffle
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: 'Aleatorio',
                        onPressed: controller.toggleShuffle,
                      ),
                      if (MediaQuery.of(context).size.width > 600) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.volume_down, size: 20),
                        SizedBox(
                          width: 80,
                          child: Slider(
                            value: controller.volume,
                            onChanged: controller.setVolume,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
