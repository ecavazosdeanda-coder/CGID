import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AudioStreamStatus {
  idle,
  connecting,
  playing,
  paused,
  error,
}

class AudioStreamState {
  final AudioStreamStatus status;
  final String streamUrl;
  final String title;
  final Duration elapsed;
  final double volume;
  final String? errorMessage;
  final double estimatedDataUsageMb; // e.g. 32 kbps ~ 0.24 MB / min

  const AudioStreamState({
    this.status = AudioStreamStatus.idle,
    this.streamUrl = '',
    this.title = 'Culto en Vivo (Solo Audio)',
    this.elapsed = Duration.zero,
    this.volume = 1.0,
    this.errorMessage,
    this.estimatedDataUsageMb = 0.0,
  });

  bool get isPlaying => status == AudioStreamStatus.playing;
  bool get isConnecting => status == AudioStreamStatus.connecting;

  AudioStreamState copyWith({
    AudioStreamStatus? status,
    String? streamUrl,
    String? title,
    Duration? elapsed,
    double? volume,
    String? errorMessage,
    double? estimatedDataUsageMb,
  }) {
    return AudioStreamState(
      status: status ?? this.status,
      streamUrl: streamUrl ?? this.streamUrl,
      title: title ?? this.title,
      elapsed: elapsed ?? this.elapsed,
      volume: volume ?? this.volume,
      errorMessage: errorMessage,
      estimatedDataUsageMb: estimatedDataUsageMb ?? this.estimatedDataUsageMb,
    );
  }
}

class LowBandwidthAudioNotifier extends Notifier<AudioStreamState> {
  AudioPlayer? _player;
  Timer? _elapsedTimer;
  StreamSubscription<PlayerState>? _stateSubscription;

  @override
  AudioStreamState build() {
    ref.onDispose(() {
      _cleanup();
    });
    return const AudioStreamState();
  }

  void _cleanup() {
    _elapsedTimer?.cancel();
    _stateSubscription?.cancel();
    _player?.stop();
    _player?.dispose();
    _player = null;
  }

  AudioPlayer _getOrCreatePlayer() {
    if (_player != null) return _player!;
    final p = AudioPlayer();
    _stateSubscription = p.onPlayerStateChanged.listen((pState) {
      if (pState == PlayerState.playing) {
        state = state.copyWith(status: AudioStreamStatus.playing, errorMessage: null);
      } else if (pState == PlayerState.paused) {
        state = state.copyWith(status: AudioStreamStatus.paused);
      } else if (pState == PlayerState.stopped || pState == PlayerState.completed) {
        state = state.copyWith(status: AudioStreamStatus.idle);
      }
    });
    _player = p;
    return p;
  }

  Future<void> playStream(String url, {String? title}) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      state = state.copyWith(
        status: AudioStreamStatus.error,
        errorMessage: 'No se configuró una URL de transmisión de audio.',
      );
      return;
    }

    try {
      state = state.copyWith(
        status: AudioStreamStatus.connecting,
        streamUrl: cleanUrl,
        title: title ?? 'Culto en Vivo (Transmisión Ligera)',
        errorMessage: null,
      );

      final player = _getOrCreatePlayer();
      await player.stop();
      await player.setVolume(state.volume);
      await player.play(UrlSource(cleanUrl));

      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (state.isPlaying) {
          final newElapsed = state.elapsed + const Duration(seconds: 1);
          // Estimación a ~32-48 kbps: ~0.005 MB por segundo (~18 MB por hora de culto)
          final mb = newElapsed.inSeconds * 0.005;
          state = state.copyWith(
            elapsed: newElapsed,
            estimatedDataUsageMb: mb,
          );
        }
      });
    } catch (e) {
      state = state.copyWith(
        status: AudioStreamStatus.error,
        errorMessage: 'Error al conectar la señal de audio: $e',
      );
    }
  }

  Future<void> pause() async {
    try {
      await _player?.pause();
      state = state.copyWith(status: AudioStreamStatus.paused);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Error al pausar: $e');
    }
  }

  Future<void> resume() async {
    if (state.streamUrl.isNotEmpty) {
      try {
        state = state.copyWith(status: AudioStreamStatus.connecting);
        await _player?.resume();
        state = state.copyWith(status: AudioStreamStatus.playing);
      } catch (e) {
        // Fallback: re-play
        await playStream(state.streamUrl, title: state.title);
      }
    }
  }

  Future<void> stop() async {
    _elapsedTimer?.cancel();
    try {
      await _player?.stop();
    } catch (_) {}
    state = state.copyWith(
      status: AudioStreamStatus.idle,
      elapsed: Duration.zero,
      estimatedDataUsageMb: 0.0,
    );
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    try {
      await _player?.setVolume(clamped);
    } catch (_) {}
  }
}

final lowBandwidthAudioProvider =
    NotifierProvider<LowBandwidthAudioNotifier, AudioStreamState>(
  () => LowBandwidthAudioNotifier(),
);
