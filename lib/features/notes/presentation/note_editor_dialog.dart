import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenant/providers/tenant_provider.dart';
import '../models/sermon_note_model.dart';
import '../providers/notes_provider.dart';

class NoteEditorDialog extends ConsumerStatefulWidget {
  final SermonNote? initialNote;
  final String? initialBibleReference;
  final String? initialHymnReference;

  const NoteEditorDialog({
    super.key,
    this.initialNote,
    this.initialBibleReference,
    this.initialHymnReference,
  });

  static Future<void> show(
    BuildContext context, {
    SermonNote? note,
    String? bibleReference,
    String? hymnReference,
  }) {
    return showDialog(
      context: context,
      builder: (_) => NoteEditorDialog(
        initialNote: note,
        initialBibleReference: bibleReference,
        initialHymnReference: hymnReference,
      ),
    );
  }

  @override
  ConsumerState<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends ConsumerState<NoteEditorDialog> {
  late TextEditingController _titleController;
  late TextEditingController _preacherController;
  late TextEditingController _churchController;
  late TextEditingController _bibleController;
  late TextEditingController _hymnController;
  late TextEditingController _contentController;
  late DateTime _selectedDate;
  List<String> _tags = [];

  final List<String> _suggestedTags = [
    'Sermón de Sábado',
    'Escuela Sabática',
    'Doctrina',
    'Oración',
    'Fe',
    'Familia',
    'Juventud',
    'Evangelismo',
  ];

  @override
  void initState() {
    super.initState();
    final note = widget.initialNote;
    final activeChurch = ref.read(tenantProvider).value;

    _titleController = TextEditingController(text: note?.title ?? '');
    _preacherController = TextEditingController(text: note?.preacher ?? '');
    _churchController = TextEditingController(
      text: note?.churchName.isNotEmpty == true
          ? note!.churchName
          : (activeChurch?.name ?? ''),
    );
    _bibleController = TextEditingController(
      text: note?.bibleReference.isNotEmpty == true
          ? note!.bibleReference
          : (widget.initialBibleReference ?? ''),
    );
    _hymnController = TextEditingController(
      text: note?.hymnReference.isNotEmpty == true
          ? note!.hymnReference
          : (widget.initialHymnReference ?? ''),
    );
    _contentController = TextEditingController(text: note?.content ?? '');
    _selectedDate = note?.date ?? DateTime.now();
    _tags = List.from(note?.tags ?? []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _preacherController.dispose();
    _churchController.dispose();
    _bibleController.dispose();
    _hymnController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor escribe un título para la nota.')),
      );
      return;
    }

    final note = SermonNote(
      id: widget.initialNote?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      preacher: _preacherController.text.trim(),
      churchName: _churchController.text.trim(),
      date: _selectedDate,
      bibleReference: _bibleController.text.trim(),
      hymnReference: _hymnController.text.trim(),
      content: _contentController.text.trim(),
      tags: _tags,
      updatedAt: DateTime.now(),
    );

    ref.read(notesProvider.notifier).saveNote(note);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nota guardada en tu cuaderno personal.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.initialNote == null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_note,
                      color: Color(0xFF10B981),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNew ? 'Nueva Nota de Sermón / Estudio' : 'Editar Nota de Culto',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Cuaderno espiritual personal (Guardado local offline)',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable Form
              Expanded(
                child: ListView(
                  children: [
                    // Título
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Tema o Título del Sermón *',
                        hintText: 'Ej. El Poder de la Oración en Tiempos Difíciles',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.title, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Predicador y Fecha
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _preacherController,
                            decoration: const InputDecoration(
                              labelText: 'Predicador / Expositor',
                              hintText: 'Ej. Pbro. Daniel Silva',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.person_outline, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fecha',
                                border: OutlineInputBorder(),
                                isDense: true,
                                prefixIcon: Icon(Icons.calendar_today, size: 18),
                              ),
                              child: Text(
                                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Congregación
                    TextField(
                      controller: _churchController,
                      decoration: const InputDecoration(
                        labelText: 'Congregación / Templo',
                        hintText: 'Ej. Templo Bethel · Monterrey',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.church_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Cita Bíblica e Himno
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bibleController,
                            decoration: const InputDecoration(
                              labelText: 'Cita Bíblica Base',
                              hintText: 'Ej. Santiago 5:13-18',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.menu_book, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _hymnController,
                            decoration: const InputDecoration(
                              labelText: 'Himno Relacionado',
                              hintText: 'Ej. Himno 125',
                              border: OutlineInputBorder(),
                              isDense: true,
                              prefixIcon: Icon(Icons.music_note, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Contenido / Bosquejo
                    const Text(
                      'Bosquejo, Notas y Puntos Principales:',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _contentController,
                      maxLines: 10,
                      minLines: 6,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                      decoration: InputDecoration(
                        hintText: '1. Introducción...\n2. Puntos del sermón...\n3. Aplicación a la vida diaria...\n4. Citas adicionales...',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Etiquetas (Tags)
                    const Text(
                      'Etiquetas / Categoría:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _suggestedTags.map((tag) {
                        final isSelected = _tags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _tags.add(tag);
                              } else {
                                _tags.remove(tag);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isNew)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Compartir Bosquejo'),
                      onPressed: () {
                        final note = widget.initialNote!;
                        Clipboard.setData(ClipboardData(text: note.toShareableText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bosquejo copiado al portapapeles listo para compartir por WhatsApp.'),
                          ),
                        );
                      },
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Guardar Nota'),
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
