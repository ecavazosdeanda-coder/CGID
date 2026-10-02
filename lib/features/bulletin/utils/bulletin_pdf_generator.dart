import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../content.dart';

class BulletinPdfGenerator {
  static Future<Uint8List> generateBulletin(
    String title,
    List<Entry> plan, {
    String churchName = 'Conferencia General de la Iglesia de Dios',
    ServicePlanMetadata metadata = const ServicePlanMetadata(),
    bool compress = true,
  }) async {
    final pdf = pw.Document(compress: compress);

    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/roboto-bold.ttf'),
    );
    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: regularFont,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: theme,
        header: (context) {
          return pw.Column(
            children: [
              pw.Text(
                churchName,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                'Columna y Apoyo de la Verdad',
                style: const pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 10),
            ],
          );
        },
        build: (context) {
          return [
            pw.Center(
              child: pw.Text(
                title.isEmpty ? 'Boletín Litúrgico' : title,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 20),
            if (metadata.serviceDate.isNotEmpty ||
                metadata.assignments.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    if (metadata.serviceDate.isNotEmpty)
                      pw.Text('Fecha: ${_formatDate(metadata.serviceDate)}'),
                    if (metadata.personFor('presidente').isNotEmpty)
                      pw.Text(
                        'Presidente: ${metadata.personFor('presidente')}',
                      ),
                    if (metadata.personFor('predicador').isNotEmpty)
                      pw.Text(
                        'Predicador: ${metadata.personFor('predicador')}',
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],
            ...plan.asMap().entries.map((e) {
              final index = e.key + 1;
              final entry = e.value;
              return _buildEntryItem(index, entry);
            }),
            pw.SizedBox(height: 30),
            pw.Center(
              child: pw.Text(
                '"Dios es Espíritu; y los que le adoran, en espíritu y en verdad es necesario que adoren." Juan 4:24',
                style: pw.TextStyle(
                  fontStyle: pw.FontStyle.italic,
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ];
        },
        footer: (context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildEntryItem(int index, Entry entry) {
    final publicData = publicEntryData(entry);
    final firstSectionText = publicData['firstSectionText']!;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.blue800, width: 3),
        ),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$index. ${publicData['title']}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (publicData['subtitle']!.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                publicData['subtitle']!,
                style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
            ),
          if (publicData['responsible']!.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(
                publicData['responsible']!,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
            ),
          if (firstSectionText.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                _truncateHymn(firstSectionText),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Public fields allowed to leave the device in a shared bulletin.
  /// Private plan notes are deliberately excluded here.
  static Map<String, String> publicEntryData(Entry entry) => {
    'title': entry.title,
    'subtitle': entry.subtitle,
    'firstSectionText': entry.sections.isEmpty ? '' : entry.sections.first.text,
    'responsible': entry.assignments
        .where(
          (assignment) =>
              assignment.showInBulletin && assignment.displayName.isNotEmpty,
        )
        .map(
          (assignment) => '${assignment.roleLabel}: ${assignment.displayName}',
        )
        .join(' · '),
  };

  static String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day}/${date.month}/${date.year}';
  }

  static String _truncateHymn(String content) {
    final blocks = content.split('\n');
    if (blocks.isEmpty) return '';
    final text = blocks.first.trim();
    if (text.length > 100) {
      return '${text.substring(0, 100)}...';
    }
    return text;
  }
}
