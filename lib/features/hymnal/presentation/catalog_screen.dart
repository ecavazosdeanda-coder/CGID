import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../content.dart';
import '../../../playback.dart';
import '../../../glass.dart';
import '../../../main.dart' show digitalScorePages;

class CatalogScreen extends StatefulWidget {
  final List<Entry> all;
  final PlaybackController playback;
  final Library lib;
  final Entry? selected;
  final void Function(Entry) onOpenEntry;
  final Widget Function(Entry, {bool modal}) readerBuilder;
  final Color accentPanel;
  final Color accentText;

  const CatalogScreen({
    super.key,
    required this.all,
    required this.playback,
    required this.lib,
    required this.selected,
    required this.onOpenEntry,
    required this.readerBuilder,
    required this.accentPanel,
    required this.accentText,
  });

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String query = '';
  final search = TextEditingController();
  bool favoritesOnly = false;
  bool hymnScoresOnly = false;
  String hymnCategoryFilter = 'Todas';
  String hymnComposerFilter = 'Todos';

  Set<String> favorites = {};
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      favorites = (prefs?.getStringList('favorites') ?? []).toSet();
    });
  }

  void favorite(Entry e) {
    setState(() {
      if (!favorites.add(e.id)) favorites.remove(e.id);
    });
    prefs?.setStringList('favorites', favorites.toList());
  }

  String hymnCategory(Entry hymn) => hymn.subtitle.split(' · ').first;

  String hymnComposer(Entry hymn) {
    final match = RegExp(
      r'm[úu]sica\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(hymn.subtitle);
    return match?.group(1)?.trim().isNotEmpty == true
        ? match!.group(1)!.trim()
        : 'No especificado';
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.all;
    final isHymnal = all.isNotEmpty && all.first.id.startsWith('h');
    final categories = isHymnal
        ? (all.map(hymnCategory).toSet().toList()..sort())
        : const <String>[];
    final composers = isHymnal
        ? (all.map(hymnComposer).toSet().toList()..sort())
        : const <String>[];
    final results = all
        .where(
          (e) =>
              (!favoritesOnly || favorites.contains(e.id)) &&
              (!isHymnal ||
                  hymnCategoryFilter == 'Todas' ||
                  hymnCategory(e) == hymnCategoryFilter) &&
              (!isHymnal ||
                  hymnComposerFilter == 'Todos' ||
                  hymnComposer(e) == hymnComposerFilter) &&
              (!isHymnal ||
                  !hymnScoresOnly ||
                  digitalScorePages.containsKey(e.id)) &&
              (query.isEmpty || e.searchable.contains(normalized(query))),
        )
        .toList();

    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: TextField(
            controller: search,
            decoration: const InputDecoration(
              hintText: 'Número, título o palabras…',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${results.length} resultados'),
              FilterChip(
                label: const Text('Favoritos'),
                selected: favoritesOnly,
                onSelected: (v) => setState(() => favoritesOnly = v),
              ),
              if (isHymnal)
                FilterChip(
                  label: const Text('Con partitura digital'),
                  selected: hymnScoresOnly,
                  onSelected: (v) => setState(() => hymnScoresOnly = v),
                ),
              if (isHymnal)
                DropdownButton<String>(
                  isExpanded: true,
                  value: hymnCategoryFilter,
                  items: [
                    const DropdownMenuItem(
                      value: 'Todas',
                      child: Text('Tipo: todos'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category,
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => hymnCategoryFilter = value!),
                ),
              if (isHymnal)
                DropdownButton<String>(
                  isExpanded: true,
                  value: hymnComposerFilter,
                  items: [
                    const DropdownMenuItem(
                      value: 'Todos',
                      child: Text('Compositor: todos'),
                    ),
                    for (final composer in composers)
                      DropdownMenuItem(
                        value: composer,
                        child: Text(
                          composer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => hymnComposerFilter = value!),
                ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('No se encontraron coincidencias.'))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final e = results[i];
                    return ListTile(
                      selected: widget.selected?.id == e.id,
                      leading: CircleAvatar(
                        backgroundColor: widget.accentPanel,
                        child: Text(
                          e.id.startsWith('hrecording')
                              ? '?'
                              : e.id.substring(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(e.title, maxLines: 2),
                      subtitle: Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Favorito',
                        icon: Icon(
                          favorites.contains(e.id)
                              ? Icons.star
                              : Icons.star_border,
                        ),
                        onPressed: () => favorite(e),
                      ),
                      onTap: () {
                        widget.onOpenEntry(e);
                      },
                    );
                  },
                ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, b) => Padding(
        padding: const EdgeInsets.all(18),
        child: b.maxWidth > 900
            ? Row(
                children: [
                  SizedBox(
                    width: 390,
                    child: GlassSurface(radius: 20, child: list),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassSurface(
                      radius: 20,
                      child: widget.readerBuilder(
                        widget.selected ?? all.first,
                        modal: false,
                      ),
                    ),
                  ),
                ],
              )
            : GlassSurface(radius: 20, child: list),
      ),
    );
  }
}
