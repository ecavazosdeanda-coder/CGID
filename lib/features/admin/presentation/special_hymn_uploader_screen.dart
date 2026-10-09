import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../hymnal/models/special_hymn_model.dart';
import '../../hymnal/providers/special_hymns_provider.dart';
import '../../tenant/providers/tenant_provider.dart';
import 'package:uuid/uuid.dart';

class SpecialHymnUploaderScreen extends ConsumerStatefulWidget {
  const SpecialHymnUploaderScreen({super.key});

  @override
  ConsumerState<SpecialHymnUploaderScreen> createState() =>
      _SpecialHymnUploaderScreenState();
}

class _SpecialHymnUploaderScreenState extends ConsumerState<SpecialHymnUploaderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contextController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _chordsController = TextEditingController();

  bool _isUploading = false;
  Uint8List? _audioBytes;
  String? _audioFileName;
  
  Uint8List? _sheetBytes;
  String? _sheetFileName;

  @override
  void dispose() {
    _titleController.dispose();
    _contextController.dispose();
    _lyricsController.dispose();
    _chordsController.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final file = await FilePicker.pickFile(
      type: FileType.audio,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _audioBytes = bytes;
        _audioFileName = file.name;
      });
    }
  }

  Future<void> _pickSheet() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'xml', 'musicxml'],
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _sheetBytes = bytes;
        _sheetFileName = file.name;
      });
    }
  }

  Future<void> _uploadHymn() async {
    if (!_formKey.currentState!.validate()) return;

    final church = await ref.read(tenantProvider.future);
    if (church == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No se detectó la iglesia actual')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    try {
      final service = ref.read(specialHymnServiceProvider);
      final hymnId = const Uuid().v4();
      
      String? audioUrl;
      if (_audioBytes != null) {
        audioUrl = await service.uploadMediaFile(
          churchId: church.id,
          hymnId: hymnId,
          folder: 'audio',
          fileName: _audioFileName!,
          fileBytes: _audioBytes!,
          contentType: 'audio/mpeg',
        );
      }

      String? sheetUrl;
      if (_sheetBytes != null) {
        sheetUrl = await service.uploadMediaFile(
          churchId: church.id,
          hymnId: hymnId,
          folder: 'sheets',
          fileName: _sheetFileName!,
          fileBytes: _sheetBytes!,
          contentType: _sheetFileName!.endsWith('.pdf') ? 'application/pdf' : 'application/xml',
        );
      }

      final newHymn = SpecialHymn(
        id: hymnId,
        title: _titleController.text.trim(),
        churchId: church.id,
        eventContext: _contextController.text.trim().isNotEmpty ? _contextController.text.trim() : null,
        lyrics: _lyricsController.text.trim().isNotEmpty ? _lyricsController.text.trim() : null,
        chords: _chordsController.text.trim().isNotEmpty ? _chordsController.text.trim() : null,
        audioStorageUrl: audioUrl,
        sheetMusicStorageUrl: sheetUrl,
        createdAt: DateTime.now(),
        uploadedBy: 'admin', // Idealmente usar FirebaseAuth.instance.currentUser?.uid
      );

      await service.createHymn(newHymn);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Himno especial publicado con éxito')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir el himno: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subir Himno Especial'),
      ),
      body: _isUploading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título del Himno *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Ingresa el título'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _contextController,
                      decoration: const InputDecoration(
                        labelText: 'Contexto o Evento (Ej. Aniversario Bethel)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lyricsController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Letra del himno (Opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _chordsController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Letra con Acordes (Opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Archivos Multimedia (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickAudio,
                            icon: const Icon(Icons.audio_file),
                            label: Text(_audioFileName ?? 'Subir Audio (.mp3)'),
                          ),
                        ),
                        if (_audioBytes != null)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red),
                            onPressed: () => setState(() {
                              _audioBytes = null;
                              _audioFileName = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickSheet,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: Text(_sheetFileName ?? 'Subir Partitura (.pdf/.xml)'),
                          ),
                        ),
                        if (_sheetBytes != null)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red),
                            onPressed: () => setState(() {
                              _sheetBytes = null;
                              _sheetFileName = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _uploadHymn,
                      child: const Text('Guardar y Publicar Himno', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
