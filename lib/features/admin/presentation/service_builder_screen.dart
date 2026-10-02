import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workspace/providers/plan_provider.dart';
import '../../workspace/providers/library_provider.dart';
import '../../tenant/providers/tenant_provider.dart';
import '../../bulletin/utils/bulletin_pdf_generator.dart';
import 'ai_liturgical_dialog.dart';
import 'package:printing/printing.dart';
import '../../../content.dart';

class ServiceBuilderScreen extends ConsumerStatefulWidget {
  final Future<void> Function(Entry entry)? onPresent;

  const ServiceBuilderScreen({super.key, this.onPresent});

  @override
  ConsumerState<ServiceBuilderScreen> createState() =>
      _ServiceBuilderScreenState();
}

class _ServiceBuilderScreenState extends ConsumerState<ServiceBuilderScreen> {
  final TextEditingController _itemController = TextEditingController();
  String _selectedType = 'Alabanza';

  final List<String> _activityTypes = [
    'Bienvenida',
    'Alabanza',
    'Himno',
    'Lectura Bíblica',
    'Oración',
    'Especial',
    'Predicación',
    'Clausura',
    'Avisos',
  ];

  final List<String> _planTemplates = [
    'Culto del sábado',
    'Escuela Sabática',
    'Sociedad de Jóvenes',
    'Culto de Oración (Martes)',
  ];

  // Variables para la selección estructurada de Biblia
  int? _selectedBibleBookIndex = 0;
  int? _selectedBibleChapterIndex = 0;
  int? _selectedBibleStartVerse = 1;
  int? _selectedBibleEndVerse = 1;

  // Variables para la selección estructurada de Himnos
  Entry? _selectedHymn;

  // CACHE para evitar lag
  List<DropdownMenuEntry<int>>? _bookEntriesCache;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _createPlan() async {
    final controller = TextEditingController(
      text: 'Culto ${DateTime.now().day}-${DateTime.now().month}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo orden de culto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre del culto',
            hintText: 'Ej. Culto matutino 12 de octubre',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final alreadyExists = ref.read(planProvider).savedPlans.containsKey(name);
    ref.read(planProvider.notifier).createPlan(name);
    _showMessage(
      alreadyExists
          ? 'El orden "$name" ya existía y fue abierto sin sobrescribirlo.'
          : 'Orden "$name" creado. Los cambios se guardan automáticamente.',
    );
  }

  Future<void> _clearPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Vaciar este orden?'),
        content: const Text(
          'Se quitarán todos sus elementos. Esta acción se guarda inmediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Vaciar orden'),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(planProvider.notifier).clearPlan();
  }

  Future<void> _presentEntry(Entry entry) async {
    final present = widget.onPresent;
    if (present == null) return;
    await present(entry);
    if (mounted) Navigator.of(context).pop();
  }

  void _removeEntry(int index, Entry entry) {
    ref.read(planProvider.notifier).removeEntry(index);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${entry.title} se quitó del orden.'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () =>
              ref.read(planProvider.notifier).insertEntry(index, entry),
        ),
      ),
    );
  }

  Future<void> _editEntry(int index, Entry entry) async {
    final titleController = TextEditingController(text: entry.title);
    final notesController = TextEditingController(text: entry.notes);
    var type = _activityTypes.contains(entry.subtitle)
        ? entry.subtitle
        : (_activityTypes.contains(_selectedType) ? _selectedType : 'Alabanza');
    final updated = await showDialog<Entry>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar elemento del orden'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: _activityTypes
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota privada para el operador',
                    helperText:
                        'No se muestra en el proyector ni en el boletín.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  entry.copyWith(
                    title: title,
                    subtitle: type,
                    notes: notesController.text.trim(),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    notesController.dispose();
    if (updated != null) {
      ref.read(planProvider.notifier).replaceEntry(index, updated);
    }
  }

  void _addCustomEntry(String text) {
    if (text.trim().isNotEmpty) {
      final entry = Entry(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        title: text.trim(),
        subtitle: _selectedType,
        pdf: '',
        page: 1,
        sections: const [],
        mediaIds: const [],
        notes: '',
      );
      ref.read(planProvider.notifier).addEntry(entry);
      _itemController.clear();
    }
  }

  void _addLibraryEntry(Entry entry, String category) {
    final newEntry = Entry(
      id: entry.id,
      title: entry.title,
      subtitle: category,
      pdf: entry.pdf,
      page: entry.page,
      sections: entry.sections,
      mediaIds: entry.mediaIds,
      notes: entry.notes,
    );
    ref.read(planProvider.notifier).addEntry(newEntry);
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'Himno':
      case 'Alabanza':
      case 'Especial':
        return Icons.music_note;
      case 'Lectura Bíblica':
        return Icons.menu_book;
      case 'Oración':
        return Icons.front_hand;
      case 'Predicación':
        return Icons.record_voice_over;
      case 'Avisos':
        return Icons.campaign;
      default:
        return Icons.article;
    }
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(planProvider);
    final activePlan = planState.activePlan;
    final plan = planState.plan;
    final libraryAsync = ref.watch(libraryProvider);
    final planNames = <String>{
      ..._planTemplates,
      ...planState.savedPlans.keys,
      activePlan,
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Constructor Litúrgico'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activePlan,
                dropdownColor: Theme.of(context).cardColor,
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                items: planNames.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  if (newValue != null) {
                    ref.read(planProvider.notifier).setActivePlan(newValue);
                  }
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Crear un nuevo orden',
            onPressed: _createPlan,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: DropdownButton<String>(
                        value: _selectedType,
                        items: _activityTypes.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedType = newValue;
                              _itemController.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: libraryAsync.when(
                        data: (library) {
                          if (_selectedType == 'Lectura Bíblica') {
                            // CASCADING BIBLE DROPDOWNS
                            final books = library.bible;
                            final currentBook =
                                books[_selectedBibleBookIndex ?? 0];
                            final chapters = currentBook['chapters'] as List;
                            final currentChapter =
                                chapters[_selectedBibleChapterIndex ?? 0];
                            final verses = currentChapter['verses'] as List;

                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                DropdownMenu<int>(
                                  initialSelection: _selectedBibleBookIndex,
                                  label: const Text('Libro'),
                                  dropdownMenuEntries: _bookEntriesCache ??=
                                      List.generate(books.length, (i) {
                                        return DropdownMenuEntry(
                                          value: i,
                                          label: books[i]['name'],
                                        );
                                      }),
                                  onSelected: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedBibleBookIndex = val;
                                        _selectedBibleChapterIndex = 0;
                                        _selectedBibleStartVerse = 1;
                                        _selectedBibleEndVerse = 1;
                                      });
                                    }
                                  },
                                ),
                                DropdownMenu<int>(
                                  key: ValueKey('cap-$_selectedBibleBookIndex'),
                                  initialSelection: _selectedBibleChapterIndex,
                                  label: const Text('Capítulo'),
                                  dropdownMenuEntries: List.generate(
                                    chapters.length,
                                    (i) {
                                      return DropdownMenuEntry(
                                        value: i,
                                        label: 'Cap. ${i + 1}',
                                      );
                                    },
                                  ),
                                  onSelected: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedBibleChapterIndex = val;
                                        _selectedBibleStartVerse = 1;
                                        _selectedBibleEndVerse = 1;
                                      });
                                    }
                                  },
                                ),
                                DropdownMenu<int>(
                                  key: ValueKey(
                                    'vstart-$_selectedBibleBookIndex-$_selectedBibleChapterIndex',
                                  ),
                                  initialSelection: _selectedBibleStartVerse,
                                  label: const Text('Del verso'),
                                  dropdownMenuEntries: List.generate(
                                    verses.length,
                                    (i) {
                                      return DropdownMenuEntry(
                                        value: i + 1,
                                        label: 'v. ${i + 1}',
                                      );
                                    },
                                  ),
                                  onSelected: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedBibleStartVerse = val;
                                        if ((_selectedBibleEndVerse ?? 1) <
                                            val) {
                                          _selectedBibleEndVerse = val;
                                        }
                                      });
                                    }
                                  },
                                ),
                                DropdownMenu<int>(
                                  key: ValueKey(
                                    'vend-$_selectedBibleBookIndex-$_selectedBibleChapterIndex-$_selectedBibleStartVerse',
                                  ),
                                  initialSelection: _selectedBibleEndVerse,
                                  label: const Text('Al verso'),
                                  dropdownMenuEntries:
                                      List.generate(verses.length, (i) {
                                            return DropdownMenuEntry(
                                              value: i + 1,
                                              label: 'v. ${i + 1}',
                                            );
                                          })
                                          .where(
                                            (e) =>
                                                e.value >=
                                                (_selectedBibleStartVerse ?? 1),
                                          )
                                          .toList(),
                                  onSelected: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedBibleEndVerse = val;
                                      });
                                    }
                                  },
                                ),
                              ],
                            );
                          } else if (_selectedType == 'Himno' ||
                              _selectedType == 'Especial') {
                            // HYMN SELECTION (LAZY LISTVIEW)
                            return OutlinedButton.icon(
                              icon: const Icon(Icons.library_music),
                              label: Text(
                                _selectedHymn?.title ??
                                    'Seleccionar Himno (Click aquí)',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                              ),
                              onPressed: () async {
                                final selected = await showDialog<Entry>(
                                  context: context,
                                  builder: (ctx) {
                                    String filter = '';
                                    return StatefulBuilder(
                                      builder: (ctx, setStateDialog) {
                                        final filtered = library.hymns
                                            .where(
                                              (h) =>
                                                  normalized(h.title).contains(
                                                    normalized(filter),
                                                  ) ||
                                                  normalized(h.id).contains(
                                                    normalized(filter),
                                                  ),
                                            )
                                            .toList();
                                        return Dialog(
                                          child: Container(
                                            width: 400,
                                            height: 500,
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              children: [
                                                const Text(
                                                  'Catálogo de Himnos',
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                TextField(
                                                  decoration:
                                                      const InputDecoration(
                                                        hintText: 'Buscar himno por número o título...',
                                                        prefixIcon: Icon(
                                                          Icons.search,
                                                        ),
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                  onChanged: (val) {
                                                    setStateDialog(() {
                                                      filter = val;
                                                    });
                                                  },
                                                ),
                                                const SizedBox(height: 12),
                                                Expanded(
                                                  child: ListView.builder(
                                                    itemCount: filtered.length,
                                                    itemBuilder: (ctx, i) {
                                                      return ListTile(
                                                        leading: const Icon(
                                                          Icons.music_note,
                                                          color:
                                                              Colors.blueAccent,
                                                        ),
                                                        title: Text(
                                                          filtered[i].title,
                                                        ),
                                                        onTap: () {
                                                          Navigator.pop(
                                                            ctx,
                                                            filtered[i],
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                                if (selected != null) {
                                  setState(() {
                                    _selectedHymn = selected;
                                  });
                                }
                              },
                            );
                          } else {
                            return TextField(
                              controller: _itemController,
                              decoration: InputDecoration(
                                hintText: 'Descripción de la actividad',
                                border: const OutlineInputBorder(),
                                prefixIcon: Icon(
                                  _getIconForType(_selectedType),
                                ),
                              ),
                              onSubmitted: (val) => _addCustomEntry(val),
                            );
                          }
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const Text('Error cargando librería'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir al Culto'),
                        onPressed: () {
                          libraryAsync.whenData((library) {
                            if (_selectedType == 'Lectura Bíblica') {
                              final b = _selectedBibleBookIndex ?? 0;
                              final c = _selectedBibleChapterIndex ?? 0;
                              final start = _selectedBibleStartVerse ?? 1;
                              final end = _selectedBibleEndVerse ?? 1;
                              final entry = library.passage(b, c, start, end);
                              _addLibraryEntry(entry, 'Lectura Bíblica');
                            } else if (_selectedType == 'Himno' ||
                                _selectedType == 'Especial') {
                              if (_selectedHymn != null) {
                                _addLibraryEntry(_selectedHymn!, _selectedType);
                                setState(() {
                                  _selectedHymn = null;
                                });
                              } else {
                                _showMessage('Selecciona primero un himno.');
                              }
                            } else {
                              if (_itemController.text.trim().isNotEmpty) {
                                _addCustomEntry(_itemController.text);
                              }
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${plan.length} ${plan.length == 1 ? 'elemento' : 'elementos'} · Guardado automáticamente en este dispositivo',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (plan.isNotEmpty) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => AiLiturgicalDialog.show(context),
                    icon: const Icon(Icons.auto_awesome, color: Colors.blueAccent),
                    label: const Text('Sugerir con IA'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final tenant = ref.read(tenantProvider).value;
                        final churchName = tenant?.name ?? 'Conferencia General de la Iglesia de Dios';
                        final pdfBytes = await BulletinPdfGenerator.generateBulletin(
                          'Orden del Culto',
                          plan,
                          churchName: churchName,
                        );
                        await Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: 'boletin_liturgico.pdf',
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al generar boletín: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
                    label: const Text('Boletín PDF'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _clearPlan,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Vaciar orden'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: plan.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.format_list_bulleted,
                            size: 64,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'El plan de culto está vacío.',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const Text(
                            'Agrega himnos, lecturas y oraciones arriba.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: plan.length,
                      onReorderItem: (oldIndex, newIndex) => ref
                          .read(planProvider.notifier)
                          .moveEntry(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final entry = plan[index];
                        final slideCount = makeSlides(entry).length;
                        return Card(
                          key: ValueKey('${entry.id}-$index'),
                          elevation: 1,
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            onTap: widget.onPresent == null
                                ? null
                                : () => _presentEntry(entry),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueAccent.withValues(
                                alpha: 0.1,
                              ),
                              child: Icon(
                                _getIconForType(entry.subtitle),
                                color: Colors.blueAccent,
                              ),
                            ),
                            title: Text(
                              entry.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${entry.subtitle.isEmpty ? 'Sección del culto' : entry.subtitle} · $slideCount ${slideCount == 1 ? 'diapositiva' : 'diapositivas'}${entry.notes.isEmpty ? '' : ' · Con nota privada'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.onPresent != null)
                                  IconButton(
                                    tooltip: 'Proyectar y abrir la consola',
                                    icon: const Icon(Icons.cast),
                                    onPressed: () => _presentEntry(entry),
                                  ),
                                IconButton(
                                  tooltip: 'Editar título, tipo o nota',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editEntry(index, entry),
                                ),
                                const Icon(
                                  Icons.drag_handle,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeEntry(index, entry),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
