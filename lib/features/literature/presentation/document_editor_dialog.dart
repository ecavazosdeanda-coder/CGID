import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/document_model.dart';
import '../providers/literature_provider.dart';

class DocumentEditorDialog extends ConsumerStatefulWidget {
  final DocumentModel? document;

  const DocumentEditorDialog({super.key, this.document});

  static Future<void> show(BuildContext context, {DocumentModel? document}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentEditorDialog(document: document),
    );
  }

  @override
  ConsumerState<DocumentEditorDialog> createState() =>
      _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends ConsumerState<DocumentEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _authorController;
  late final TextEditingController _yearController;
  late final TextEditingController _urlController;
  late final TextEditingController _assetPathController;

  late DocumentCategory _selectedCategory;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final doc = widget.document;
    _titleController = TextEditingController(text: doc?.title ?? '');
    _descriptionController =
        TextEditingController(text: doc?.description ?? '');
    _authorController = TextEditingController(
      text: doc?.author ?? 'Conferencia General de la Iglesia de Dios',
    );
    _yearController = TextEditingController(
      text: doc?.year ?? DateTime.now().year.toString(),
    );
    _urlController = TextEditingController(text: doc?.url ?? '');
    _assetPathController = TextEditingController(text: doc?.assetPath ?? '');
    _selectedCategory = doc?.category ?? DocumentCategory.puntosDeFe;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _yearController.dispose();
    _urlController.dispose();
    _assetPathController.dispose();
    super.dispose();
  }

  String _getCategoryLabel(DocumentCategory cat) {
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

  String _generateSlug(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final url = _urlController.text.trim();
    final assetPath = _assetPathController.text.trim();

    if (url.isEmpty && assetPath.isEmpty) {
      setState(() {
        _errorMessage =
            'Debes ingresar al menos una URL o una ruta de archivo PDF.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final docId = widget.document?.id ??
          'doc-${_generateSlug(_titleController.text.trim())}-${DateTime.now().millisecondsSinceEpoch % 10000}';

      final newDoc = DocumentModel(
        id: docId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        author: _authorController.text.trim(),
        year: _yearController.text.trim(),
        url: url.isNotEmpty ? url : null,
        assetPath: assetPath.isNotEmpty ? assetPath : null,
      );

      await ref.read(literatureProvider.notifier).addOrUpdateDocument(newDoc);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              widget.document == null
                  ? 'Literatura agregada y sincronizada exitosamente.'
                  : 'Literatura actualizada correctamente.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Error al guardar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.document != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_note : Icons.post_add,
            color: Colors.indigo,
          ),
          const SizedBox(width: 8),
          Text(isEditing ? 'Editar Literatura' : 'Subir Nueva Literatura'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El documento estará disponible para todos los miembros, invitados y templos de la Conferencia.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título de la Publicación *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Ingresa el título' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Resumen *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Ingresa una breve descripción'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<DocumentCategory>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Categoría *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: DocumentCategory.values.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(_getCategoryLabel(cat)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _authorController,
                        decoration: const InputDecoration(
                          labelText: 'Autor / Departamento',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _yearController,
                        decoration: const InputDecoration(
                          labelText: 'Año',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Enlace web / URL del archivo PDF',
                    hintText: 'https://ejemplo.org/documento.pdf',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Puedes enlazar un archivo PDF de Google Drive (enlace público), Dropbox, o tu servidor.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withAlpha(50)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(_isSaving ? 'Guardando...' : 'Guardar Documento'),
        ),
      ],
    );
  }
}
