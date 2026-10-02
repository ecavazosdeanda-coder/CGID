import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sermon_note_model.dart';

final notesProvider = NotifierProvider<NotesNotifier, List<SermonNote>>(() {
  return NotesNotifier();
});

class NotesNotifier extends Notifier<List<SermonNote>> {
  static const String _storageKey = 'cgdi_sermon_notes';

  @override
  List<SermonNote> build() {
    _loadNotes();
    return const [];
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final list = decoded
            .map((item) => SermonNote.fromJson(item as Map<String, dynamic>))
            .toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        state = list;
      }
    } catch (_) {}
  }

  Future<void> saveNote(SermonNote note) async {
    final updated = List<SermonNote>.from(state);
    final idx = updated.indexWhere((n) => n.id == note.id);
    if (idx >= 0) {
      updated[idx] = note;
    } else {
      updated.insert(0, note);
    }
    updated.sort((a, b) => b.date.compareTo(a.date));
    state = updated;
    await _persist();
  }

  Future<void> deleteNote(String id) async {
    state = state.where((n) => n.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(state.map((n) => n.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }
}
