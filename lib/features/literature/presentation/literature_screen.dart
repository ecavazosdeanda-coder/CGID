import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/providers/user_profile_provider.dart';
import '../models/document_model.dart';
import '../providers/literature_provider.dart';
import 'document_editor_dialog.dart';
import 'document_viewer_screen.dart';

class LiteratureScreen extends ConsumerStatefulWidget {
  const LiteratureScreen({super.key});

  @override
  ConsumerState<LiteratureScreen> createState() => _LiteratureScreenState();
}

class _LiteratureScreenState extends ConsumerState<LiteratureScreen> {
  DocumentCategory? _selectedCategory;
  String _query = '';

  String _getCategoryName(DocumentCategory cat) {
    switch (cat) {
      case DocumentCategory.puntosDeFe:
        return 'Puntos de Fe Explicados';
      case DocumentCategory.escuelaSabatica:
        return 'Escuela Sabática';
      case DocumentCategory.estudiosDoctrinales:
        return 'Estudios Doctrinales';
      case DocumentCategory.revistasOficiales:
        return 'Revistas Oficiales';
      case DocumentCategory.otro:
        return 'Otros Documentos';
    }
  }

  void _confirmDelete(DocumentModel doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar del catálogo'),
        content: Text(
          '¿Deseas ocultar "${doc.title}" del catálogo nacional?\n\nSe sincronizará con todos los dispositivos. El PDF y los archivos locales se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(literatureProvider.notifier)
                    .deleteDocument(doc.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(
                        'Documento "${doc.title}" oculto del catálogo. El archivo se conserva.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(literatureErrorMessage(e))),
                  );
                }
              }
            },
            child: const Text('Quitar del catálogo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(literatureProvider);
    final profileAsync = ref.watch(userProfileProvider);
    final isAdmin = profileAsync.value?.isAdmin == true;

    return Scaffold(
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => DocumentEditorDialog.show(context),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.post_add),
              label: const Text('Publicar Literatura'),
            )
          : null,
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ref.read(literatureProvider.notifier).syncWarning != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ref.read(literatureProvider.notifier).syncWarning!,
                  ),
                ),
              Text('Error al cargar literatura: $e'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(literatureProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
        data: (documents) {
          final query = _query.trim().toLowerCase();
          final filteredDocs = documents.where((document) {
            final matchesCategory =
                _selectedCategory == null ||
                document.category == _selectedCategory;
            final matchesQuery =
                query.isEmpty ||
                '${document.title} ${document.description} ${document.author}'
                    .toLowerCase()
                    .contains(query);
            return matchesCategory && matchesQuery;
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (ref.read(literatureProvider.notifier).syncWarning != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    ref.read(literatureProvider.notifier).syncWarning!,
                  ),
                ),
              // Barra de Búsqueda y Botón Refrescar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar título, autor o tema',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Sincronizar catálogo',
                      onPressed: () =>
                          ref.read(literatureProvider.notifier).refresh(),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: () => DocumentEditorDialog.show(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Publicar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Filtros por Categoría
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: const Text('Todos'),
                        selected: _selectedCategory == null,
                        onSelected: (val) {
                          setState(() => _selectedCategory = null);
                        },
                      ),
                    ),
                    ...DocumentCategory.values.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(_getCategoryName(cat)),
                          selected: _selectedCategory == cat,
                          onSelected: (val) {
                            setState(
                              () => _selectedCategory = val ? cat : null,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Lista de Documentos
              Expanded(
                child: filteredDocs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay publicaciones visibles. Los originales locales están ocultos de Literatura; sus archivos se conservan.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withAlpha(20),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf,
                                  size: 32,
                                  color: Colors.redAccent,
                                ),
                              ),
                              title: Text(
                                doc.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.description,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Chip(
                                          label: Text(
                                            _getCategoryName(doc.category),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${doc.author} • ${doc.year}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isAdmin) ...[
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: Colors.indigo,
                                      ),
                                      tooltip: 'Editar documento',
                                      onPressed: () =>
                                          DocumentEditorDialog.show(
                                            context,
                                            document: doc,
                                          ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      tooltip: 'Eliminar del catálogo',
                                      onPressed: () => _confirmDelete(doc),
                                    ),
                                  ],
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DocumentViewerScreen(document: doc),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
