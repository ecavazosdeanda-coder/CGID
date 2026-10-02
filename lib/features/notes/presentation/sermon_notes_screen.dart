import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sermon_note_model.dart';
import '../providers/notes_provider.dart';
import 'note_editor_dialog.dart';

class SermonNotesScreen extends ConsumerStatefulWidget {
  const SermonNotesScreen({super.key});

  @override
  ConsumerState<SermonNotesScreen> createState() => _SermonNotesScreenState();
}

class _SermonNotesScreenState extends ConsumerState<SermonNotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedTagFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    final theme = Theme.of(context);

    final filteredNotes = notes.where((note) {
      if (_selectedTagFilter != null && !note.tags.contains(_selectedTagFilter)) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return note.title.toLowerCase().contains(q) ||
          note.preacher.toLowerCase().contains(q) ||
          note.bibleReference.toLowerCase().contains(q) ||
          note.content.toLowerCase().contains(q) ||
          note.churchName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Text('Cuaderno de Sermones y Notas'),
          ],
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva Nota'),
            onPressed: () => NoteEditorDialog.show(context),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por tema, predicador, pasaje bíblico...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Todas'),
                          selected: _selectedTagFilter == null,
                          onSelected: (_) => setState(() => _selectedTagFilter = null),
                        ),
                        const SizedBox(width: 8),
                        ...{
                          for (final n in notes)
                            for (final t in n.tags) t
                        }.map((tag) {
                          final isSelected = _selectedTagFilter == tag;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(tag),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() {
                                  _selectedTagFilter = isSelected ? null : tag;
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Content List
          Expanded(
            child: filteredNotes.isEmpty
                ? _buildEmptyState(context, notes.isEmpty)
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = filteredNotes[index];
                      return _buildNoteCard(context, note);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(BuildContext context, SermonNote note) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => NoteEditorDialog.show(context, note: note),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Meta Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 13,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${note.date.day}/${note.date.month}/${note.date.year}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (note.preacher.isNotEmpty)
                    Text(
                      'Por: ${note.preacher}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
                      ),
                    ),
                  const Spacer(),
                  // Share button
                  IconButton(
                    icon: const Icon(Icons.share, size: 18),
                    tooltip: 'Compartir bosquejo por WhatsApp',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: note.toShareableText()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bosquejo copiado al portapapeles listo para compartir.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                    tooltip: 'Eliminar nota',
                    onPressed: () => _confirmDelete(context, note),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                note.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),

              // Bible & Church badges
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (note.bibleReference.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book, size: 13, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 5),
                          Text(
                            note.bibleReference,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (note.hymnReference.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.music_note, size: 13, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 5),
                          Text(
                            note.hymnReference,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (note.churchName.isNotEmpty)
                    Text(
                      '• ${note.churchName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Content snippet
              if (note.content.isNotEmpty)
                Text(
                  note.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
                  ),
                ),

              // Tags row
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: note.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool noNotesAtAll) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                size: 56,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              noNotesAtAll
                  ? 'Tu Cuaderno de Sermones está vacío'
                  : 'No se encontraron notas con esa búsqueda',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                noNotesAtAll
                    ? 'Anota los bosquejos de las predicaciones durante los cultos de sábado, estudios bíblicos y conferencias para repasarlos en cualquier momento.'
                    : 'Intenta con otros términos o borra los filtros de búsqueda.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.35),
              ),
            ),
            const SizedBox(height: 20),
            if (noNotesAtAll)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Tomar mi primera nota'),
                onPressed: () => NoteEditorDialog.show(context),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, SermonNote note) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar esta nota?'),
        content: Text('Se eliminará permanentemente "${note.title}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              ref.read(notesProvider.notifier).deleteNote(note.id);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nota eliminada.')),
              );
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
