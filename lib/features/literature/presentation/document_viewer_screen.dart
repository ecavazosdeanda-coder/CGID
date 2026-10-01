import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../models/document_model.dart';

class DocumentViewerScreen extends StatelessWidget {
  final DocumentModel document;

  const DocumentViewerScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        actions: [
          if (document.url != null)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Descargar Documento',
              onPressed: () {
                // Implement downloading logic here or launching URL
              },
            ),
        ],
      ),
      body: _buildPdfViewer(context),
    );
  }

  Widget _buildPdfViewer(BuildContext context) {
    final hasAsset = document.assetPath != null && document.assetPath!.isNotEmpty;
    final hasUrl = document.url != null && document.url!.isNotEmpty;

    if (hasAsset) {
      return PdfViewer.asset(
        document.assetPath!,
      );
    } else if (hasUrl) {
      return PdfViewer.uri(
        Uri.parse(document.url!),
      );
    }

    return const Center(
      child: Text('Documento no disponible (no hay archivo PDF ni URL vinculada).'),
    );
  }
}
