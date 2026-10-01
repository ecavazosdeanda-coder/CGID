import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/document_model.dart';
import 'document_viewer_screen.dart';

class LiteratureScreen extends StatefulWidget {
  const LiteratureScreen({super.key});

  @override
  State<LiteratureScreen> createState() => _LiteratureScreenState();
}

class _LiteratureScreenState extends State<LiteratureScreen> {
  List<DocumentModel> _documents = [];
  bool _loading = true;
  DocumentCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/literature_catalog.json');
      final data = jsonDecode(jsonString);
      final List<dynamic> docsJson = data['documents'];
      if (mounted) {
        setState(() {
          _documents = docsJson.map((e) => DocumentModel.fromJson(e)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredDocs = _selectedCategory == null
        ? _documents
        : _documents.where((d) => d.category == _selectedCategory).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      setState(() => _selectedCategory = val ? cat : null);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredDocs.length,
            itemBuilder: (context, index) {
              final doc = filteredDocs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.picture_as_pdf, size: 40, color: Colors.redAccent),
                  title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(doc.description),
                        const SizedBox(height: 8),
                        Text('Autor: ${doc.author} • Año: ${doc.year}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentViewerScreen(document: doc),
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
  }
}
