import 'package:flutter/material.dart';
import '../../../content.dart';
import '../../../glass.dart';
import '../../../playback.dart';
import '../../../audio_handler.dart';
class EntryReaderModal extends StatefulWidget {
  final Entry initialEntry;
  final PlaybackController playback;
  final Library lib;
  final Widget Function(Entry e, {bool modal}) readerBuilder;

  const EntryReaderModal({
    super.key,
    required this.initialEntry,
    required this.playback,
    required this.lib,
    required this.readerBuilder,
  });

  @override
  State<EntryReaderModal> createState() => _EntryReaderModalState();
}

class _EntryReaderModalState extends State<EntryReaderModal> {
  late Entry currentEntry;
  String? _trackedActiveId;

  @override
  void initState() {
    super.initState();
    currentEntry = widget.initialEntry;
    _trackedActiveId = widget.playback.activeId;
    widget.playback.addListener(_onPlaybackChanged);
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }

  void _onPlaybackChanged() {
    final activeId = widget.playback.activeId;
    if (activeId != _trackedActiveId) {
      _trackedActiveId = activeId;
      if (activeId != null &&
          activeId.startsWith('h') &&
          activeId != currentEntry.id) {
        final found = widget.lib.hymns
            .where((h) => h.id == activeId)
            .firstOrNull;
        if (found != null && mounted) {
          setState(() {
            currentEntry = found;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentEntry.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: AmbientBackground(
        child: widget.readerBuilder(currentEntry, modal: true),
      ),
    );
  }
}
