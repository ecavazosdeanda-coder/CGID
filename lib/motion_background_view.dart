import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class MotionBackgroundView extends StatefulWidget {
  final String? videoPath;

  const MotionBackgroundView({super.key, this.videoPath});

  @override
  State<MotionBackgroundView> createState() => _MotionBackgroundViewState();
}

class _MotionBackgroundViewState extends State<MotionBackgroundView> {
  Player? _player;
  VideoController? _controller;
  String? _currentPath;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    _player = Player();
    _controller = VideoController(_player!);
    if (widget.videoPath != null) {
      _loadVideo(widget.videoPath!);
    }
  }

  void _loadVideo(String path) {
    _currentPath = path;
    _player?.setPlaylistMode(PlaylistMode.loop);
    _player?.open(Media(path));
  }

  @override
  void didUpdateWidget(covariant MotionBackgroundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoPath != oldWidget.videoPath) {
      if (widget.videoPath == null) {
        _player?.stop();
        _currentPath = null;
      } else if (widget.videoPath != _currentPath) {
        _loadVideo(widget.videoPath!);
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoPath == null || _controller == null) {
      return const SizedBox.shrink();
    }
    // Wrapped in IgnorePointer so the video never captures mouse/touch/focus
    // events and the operator UI stays fully interactive.
    return IgnorePointer(
      child: SizedBox.expand(
        child: Video(
          controller: _controller!,
          controls: NoVideoControls,
          fill: Colors.transparent,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
