import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../content.dart';

class BulletinPdfGenerator {
  static Future<Uint8List> generateBulletin(String title, List<Entry> plan) async {
    final pdf = pw.Document();

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: theme,
        header: (context) {
          return pw.Column(
            children: [
              pw.Text('Iglesia de Dios', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
              pw.Text('Columna y Apoyo de la Verdad', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
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
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 20),
            ...plan.asMap().entries.map((e) {
              final index = e.key + 1;
              final entry = e.value;
              return _buildEntryItem(index, entry);
            }),
            pw.SizedBox(height: 30),
            pw.Center(
              child: pw.Text(
                '"Dios es Espíritu; y los que le adoran, en espíritu y en verdad es necesario que adoren." Juan 4:24',
                style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10, color: PdfColors.grey600),
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
    String firstSectionText = '';
    if (entry.sections.isNotEmpty) {
      firstSectionText = entry.sections.first.text;
    }
    
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: PdfColors.blue800, width: 3)),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$index. ${entry.title}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (entry.subtitle.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                entry.subtitle,
                style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
              ),
            ),
          if (firstSectionText.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                _truncateHymn(firstSectionText),
                style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800),
              ),
            ),
          if (entry.notes.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Nota: ${entry.notes}',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.blue900),
              ),
            ),
        ],
      ),
    );
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
