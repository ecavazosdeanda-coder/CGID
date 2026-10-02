import 'dart:async';

import 'package:audio_service/audio_service.dart';

/// Manejador de audio para vincular eventos de Android Auto, auriculares Bluetooth
/// (botones Play, Pause, Next, Prev) y la pantalla de bloqueo con el reproductor.
class CgidAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onStopCallback;
  Future<void> Function()? onNextCallback;
  Future<void> Function()? onPreviousCallback;
  Future<void> Function(Duration position)? onSeekCallback;
  Future<void> Function(double speed)? onSetSpeedCallback;

  CgidAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.playPause,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void updateItem({
    required String id,
    required String title,
    String? subtitle,
    Duration? hymnDuration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        album: 'Himnario CGID',
        title: title,
        artist: (subtitle != null && subtitle.isNotEmpty)
            ? subtitle
            : 'Conferencia General de la Iglesia de Dios',
        duration: hymnDuration,
      ),
    );
  }

  void updateState({
    required bool isPlaying,
    required Duration currentPosition,
    Duration? totalDuration,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        // Mantener los índices compactos en cada actualización de estado.
        // Android no los persiste entre copyWith si no se especifican de nuevo.
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: currentPosition,
        bufferedPosition: currentPosition,
      ),
    );
  }

  void resetState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
      ),
    );
  }

  @override
  Future<void> play() async => await onPlayCallback?.call();

  @override
  Future<void> pause() async => await onPauseCallback?.call();

  @override
  Future<void> stop() async {
    await onStopCallback?.call();
    resetState();
  }

  @override
  Future<void> skipToNext() async => await onNextCallback?.call();

  @override
  Future<void> skipToPrevious() async => await onPreviousCallback?.call();

  @override
  Future<void> seek(Duration position) async =>
      await onSeekCallback?.call(position);

  @override
  Future<void> setSpeed(double speed) async =>
      await onSetSpeedCallback?.call(speed);
}
