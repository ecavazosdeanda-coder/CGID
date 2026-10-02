import 'package:flutter/material.dart';

import '../../../content.dart';
import '../../../playback.dart';
import '../../../glass.dart';
import '../../../main.dart' show highlightSearchText;
import '../../hymnal/presentation/lectern_reader_screen.dart';

class BibleScreen extends StatefulWidget {
  final Library lib;
  final PlaybackController playback;
  final void Function(Entry) onPrepare;
  final void Function(Entry) onAddPlan;
  final void Function(Entry, {bool popModal}) showPassageDialog;
  final Color accentPanel;
  final Color secondaryText;
  final Color accentText;

  const BibleScreen({
    super.key,
    required this.lib,
    required this.playback,
    required this.onPrepare,
    required this.onAddPlan,
    required this.showPassageDialog,
    required this.accentPanel,
    required this.secondaryText,
    required this.accentText,
  });

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  int bibleSearchPage = 0;
  int book = 0;
  int chapter = 0;
  int startVerse = 1;
  int endVerse = 1;
  bool unlimitedVerses = true;
  String query = '';
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> showConcordance(int verse) async {
    final references = widget.lib.concordance(book, chapter, verse);
    final source = widget.lib.passage(book, chapter, verse, verse);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            shrinkWrap: true,
            children: [
              Text(
                'Concordancia bíblica',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(source.title, style: TextStyle(color: widget.secondaryText)),
              const SizedBox(height: 16),
              if (references.isEmpty)
                const Text('No hay citas relacionadas para este versículo.'),
              for (final reference in references)
                Builder(
                  builder: (_) {
                    final target = widget.lib.passage(
                      reference.book,
                      reference.chapter,
                      reference.start,
                      reference.end,
                    );
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.link),
                        title: Text(target.title),
                        subtitle: Text(
                          target.sections.map((s) => s.text).join(' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          widget.showPassageDialog(target, popModal: true);
                        },
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Text(
                'Concordancias: OpenBible.info · CC BY 4.0',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.lib.bible;
    final chapters = books[book]['chapters'] as List;
    final verses = chapters[chapter]['verses'] as List;
    final effectiveEnd = unlimitedVerses
        ? verses.last['number'] as int
        : endVerse;
    final entry = widget.lib.passage(book, chapter, startVerse, effectiveEnd);
    final matches = <Entry>[];

    if (query.trim().length >= 3) {
      final q = normalized(query);
      for (var bi = 0; bi < books.length; bi++) {
        final cs = books[bi]['chapters'] as List;
        for (var ci = 0; ci < cs.length; ci++) {
          for (final v in cs[ci]['verses']) {
            if (normalized(v['text']).contains(q)) {
              matches.add(widget.lib.passage(bi, ci, v['number'], v['number']));
            }
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        AmbientSectionHeader(
          icon: Icons.menu_book_outlined,
          title: 'Las Sagradas Escrituras',
          subtitle: widget.lib.bibleEdition,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar en la Biblia (mínimo 3 caracteres)',
          ),
          onChanged: (v) => setState(() {
            query = v;
            bibleSearchPage = 0;
          }),
        ),
        const SizedBox(height: 18),
        if (query.isNotEmpty) ...[
          Text(
            query.trim().length < 3
                ? 'Escribe al menos 3 caracteres.'
                : '${matches.length} resultados encontrados',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (final e in matches.skip(bibleSearchPage * 50).take(50))
            ListTile(
              title: Text(e.title),
              subtitle: highlightSearchText(
                context,
                e.sections.first.text,
                query,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.cast),
                onPressed: () => widget.onPrepare(e),
              ),
              onTap: () {
                final parts = e.id
                    .substring(1)
                    .split(':')
                    .map(int.parse)
                    .toList();
                setState(() {
                  book = parts[0];
                  chapter = parts[1];
                  startVerse = parts[2];
                  endVerse = parts[3];
                  unlimitedVerses = false;
                  query = '';
                  search.clear();
                });
              },
            ),
          if (matches.length > 50)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: bibleSearchPage > 0
                        ? () => setState(() => bibleSearchPage--)
                        : null,
                  ),
                  DropdownButton<int>(
                    value: bibleSearchPage,
                    items: [
                      for (
                        var page = 0;
                        page < (matches.length / 50).ceil();
                        page++
                      )
                        DropdownMenuItem(
                          value: page,
                          child: Text(
                            'Página ${page + 1} de ${(matches.length / 50).ceil()}',
                          ),
                        ),
                    ],
                    onChanged: (page) {
                      if (page != null) setState(() => bibleSearchPage = page);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: (bibleSearchPage + 1) * 50 < matches.length
                        ? () => setState(() => bibleSearchPage++)
                        : null,
                  ),
                ],
              ),
            ),
        ] else ...[
          GlassSurface(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    DropdownButton<int>(
                      value: book,
                      items: [
                        for (var i = 0; i < books.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(books[i]['name']),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        book = v!;
                        widget.playback.stop();
                        chapter = 0;
                        startVerse = endVerse = 1;
                        unlimitedVerses = true;
                      }),
                    ),
                    DropdownButton<int>(
                      value: chapter,
                      items: [
                        for (var i = 0; i < chapters.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text('Capítulo ${i + 1}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        chapter = v!;
                        widget.playback.stop();
                        startVerse = endVerse = 1;
                        unlimitedVerses = true;
                      }),
                    ),
                    DropdownButton<int>(
                      value: startVerse,
                      items: [
                        for (final v in verses)
                          DropdownMenuItem(
                            value: v['number'] as int,
                            child: Text('Desde ${v['number']}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        startVerse = v!;
                        widget.playback.stop();
                        if (endVerse < startVerse) endVerse = startVerse;
                      }),
                    ),
                    DropdownButton<int>(
                      key: const ValueKey('bible-until'),
                      value: unlimitedVerses ? 0 : endVerse,
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Hasta: sin límite'),
                        ),
                        for (final v in verses.where(
                          (v) => v['number'] >= startVerse,
                        ))
                          DropdownMenuItem(
                            value: v['number'] as int,
                            child: Text('Hasta ${v['number']}'),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        unlimitedVerses = v == 0;
                        widget.playback.stop();
                        if (v != 0) endVerse = v!;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => widget.onPrepare(entry),
                      icon: const Icon(Icons.cast),
                      label: const Text('Proyectar selección'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onAddPlan(entry),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Agregar al culto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LecternReaderScreen(entry: entry),
                        ),
                      ),
                      icon: const Icon(Icons.auto_stories),
                      label: const Text('Modo Atril / Lectura'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (unlimitedVerses)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Desde el versículo $startVerse hasta el final del capítulo.',
                style: TextStyle(color: widget.secondaryText),
              ),
            ),
          PlaybackControls(
            controller: widget.playback,
            contentId: entry.id,
            text: entry.spokenText,
          ),
          const SizedBox(height: 18),
          for (final v in verses.where(
            (v) => v['number'] >= startVerse && v['number'] <= effectiveEnd,
          ))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: v['number'] >= startVerse && v['number'] <= effectiveEnd
                  ? widget.accentPanel
                  : null,
              child: ListTile(
                onTap: () => setState(() {
                  startVerse = endVerse = v['number'];
                  widget.playback.stop();
                  unlimitedVerses = false;
                }),
                leading: Text(
                  '${v['number']}',
                  style: TextStyle(
                    color: widget.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                title: SelectableText(
                  (v['text'] as String).isEmpty
                      ? 'Esta edición no presenta texto independiente para este número.'
                      : v['text'],
                  style: const TextStyle(fontSize: 18, height: 1.65),
                ),
                trailing: IconButton(
                  tooltip: 'Ver concordancias',
                  icon: const Icon(Icons.link),
                  onPressed:
                      widget.lib
                          .concordance(book, chapter, v['number'] as int)
                          .isEmpty
                      ? null
                      : () => showConcordance(v['number'] as int),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
