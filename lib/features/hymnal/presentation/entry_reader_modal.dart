import 'package:flutter/material.dart';

import '../../../content.dart';
import '../../../glass.dart';
import '../../../playback.dart';
import 'lectern_reader_screen.dart';
import '../../notes/presentation/note_editor_dialog.dart';

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
        actions: [
          if (currentEntry.id.startsWith('h'))
            IconButton(
              icon: const Icon(Icons.queue_music),
              tooltip: 'Atril Digital (Acordes y Transposición)',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LecternReaderScreen(entry: currentEntry),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Tomar nota en mi cuaderno',
            onPressed: () {
              final isBible = currentEntry.id.startsWith('b');
              final isHymn = currentEntry.id.startsWith('h');
              NoteEditorDialog.show(
                context,
                bibleReference: isBible ? currentEntry.title : null,
                hymnReference: isHymn ? currentEntry.title : null,
              );
            },
          ),
        ],
      ),
      body: AmbientBackground(
        child: widget.readerBuilder(currentEntry, modal: true),
      ),
    );
  }
}
