import 'package:flutter/material.dart';

import '../../../content.dart';
import '../services/hymn_customization_service.dart';
import 'chord_lyrics_view.dart';

class HymnChordEditorDialog extends StatefulWidget {
  final Entry hymn;
  final List<Section> initialSections;

  const HymnChordEditorDialog({
    super.key,
    required this.hymn,
    required this.initialSections,
  });

  static Future<List<Section>?> show(
    BuildContext context, {
    required Entry hymn,
    required List<Section> initialSections,
  }) {
    if (!HymnCustomizationService.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Acceso restringido: Solo el administrador puede modificar o corregir los acordes.',
          ),
        ),
      );
      return Future.value(null);
    }
    return showDialog<List<Section>?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => HymnChordEditorDialog(
        hymn: hymn,
        initialSections: initialSections,
      ),
    );
  }

  @override
  State<HymnChordEditorDialog> createState() => _HymnChordEditorDialogState();
}

class _HymnChordEditorDialogState extends State<HymnChordEditorDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final TabController _tabController;
  final FocusNode _focusNode = FocusNode();

  static const _commonRoots = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];
  static const _commonSuffixes = ['', 'm', '7', 'm7', 'maj7', 'sus4', 'dim', 'add9'];

  String _selectedRoot = 'G';
  String _selectedSuffix = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatSectionsToText(widget.initialSections),
    );
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static String formatSectionsToText(List<Section> sections) {
    final buffer = StringBuffer();
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (s.label.isNotEmpty) {
        buffer.writeln('[${s.label.toUpperCase()}]');
      }
      buffer.writeln(s.text.trim());
      if (i < sections.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  static List<Section> parseTextToSections(String text) {
    final lines = text.split('\n');
    final sections = <Section>[];
    String currentLabel = '';
    final currentLines = <String>[];

    final sectionHeaderRegex = RegExp(
      r'^\s*\[([A-Z0-9ÁÉÍÓÚÑ\s]+)\]\s*$',
      caseSensitive: false,
    );

    for (final line in lines) {
      final match = sectionHeaderRegex.firstMatch(line.trim());
      final isHeader = match != null && _isSectionName(match.group(1)!);
      if (isHeader) {
        if (currentLines.isNotEmpty || currentLabel.isNotEmpty) {
          sections.add(Section(currentLabel, currentLines.join('\n').trim()));
          currentLines.clear();
        }
        currentLabel = match.group(1)!.trim();
      } else {
        currentLines.add(line);
      }
    }

    if (currentLines.isNotEmpty || currentLabel.isNotEmpty) {
      sections.add(Section(currentLabel, currentLines.join('\n').trim()));
    }

    return sections.isEmpty ? [Section('Letra', text.trim())] : sections;
  }

  static bool _isSectionName(String tag) {
    final upper = tag.toUpperCase().trim();
    return upper.startsWith('ESTROFA') ||
        upper.startsWith('CORO') ||
        upper.startsWith('PUENTE') ||
        upper.startsWith('FINAL') ||
        upper.startsWith('INTRO') ||
        upper.startsWith('VERSO');
  }

  void _insertChord(String chord) {
    final text = _controller.text;
    final selection = _controller.selection;
    final chordString = '[$chord]';

    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, chordString);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + chordString.length),
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  void _insertText(String snippet) {
    final text = _controller.text;
    final selection = _controller.selection;

    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final newText = text.replaceRange(start, end, snippet);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
    _focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _save() async {
    if (!HymnCustomizationService.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Acceso restringido: Solo el administrador puede guardar cambios.',
          ),
        ),
      );
      return;
    }
    final sections = parseTextToSections(_controller.text);
    final ok = await hymnCustomizationService.saveCustomChords(widget.hymn.id, sections);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.teal,
          content: Text('¡Acordes actualizados y sincronizados con éxito!'),
        ),
      );
      Navigator.of(context).pop(sections);
    }
  }

  Future<void> _resetToOriginal() async {
    if (!HymnCustomizationService.isAdmin) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar acordes del canto'),
        content: const Text(
          '¿Deseas eliminar todos los acordes guardados de este canto y dejar únicamente la letra limpia?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar acordes'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await hymnCustomizationService.clearCustomChords(widget.hymn.id);
    if (!mounted) return;
    Navigator.of(context).pop(<Section>[]);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chordCol = dark ? Colors.amberAccent : Colors.deepOrange.shade800;
    final textCol = dark ? Colors.white : Colors.black87;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Column(
          children: [
            // AppBar / Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(80),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editor de Acordes · ${widget.hymn.title}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Escribe acordes entre corchetes ej: [G]. Puedes colocarlos antes de palabras ([G]Dios) o en sílabas ([G]per[D]dón).',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
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
            ),

            // Selector rápido de acordes para insertar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: dark ? const Color(0xff121d24) : const Color(0xffeef5f2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Insertar acorde rápido:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _insertText(' '),
                        child: const Text('+ Espacio', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => _insertText('-'),
                        child: const Text('- Guion', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () => _insertChord('$_selectedRoot$_selectedSuffix'),
                        child: Text(
                          'Insertar [$_selectedRoot$_selectedSuffix]',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final root in _commonRoots)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text(root, style: const TextStyle(fontSize: 12)),
                              selected: _selectedRoot == root,
                              onSelected: (_) => setState(() => _selectedRoot = root),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final suffix in _commonSuffixes)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: FilterChip(
                              label: Text(
                                suffix.isEmpty ? 'Mayor' : suffix,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: _selectedSuffix == suffix,
                              onSelected: (_) => setState(() => _selectedSuffix = suffix),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Pestañas (Editar / Previsualizar)
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.edit, size: 18), text: 'Editar Texto'),
                Tab(icon: Icon(Icons.visibility, size: 18), text: 'Vista Previa en Vivo'),
              ],
            ),

            // Contenido de las pestañas
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Editor de texto
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '[ESTROFA 1]\n[G]Quiero cantar a mi Señor...',
                      ),
                    ),
                  ),

                  // Tab 2: Previsualización en vivo
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final sections = parseTextToSections(_controller.text);
                      return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          for (final section in sections)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: dark
                                    ? const Color(0xff182229)
                                    : const Color(0xfff1ece1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (section.label.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        section.label.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.teal,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ChordLyricsBlock(
                                    text: section.text,
                                    fontSize: 15,
                                    textCol: textCol,
                                    chordCol: chordCol,
                                    showChords: true,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            // Barra inferior con acciones
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(80),
                  ),
                ),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400),
                    onPressed: _resetToOriginal,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Borrar acordes'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Guardar Acordes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
