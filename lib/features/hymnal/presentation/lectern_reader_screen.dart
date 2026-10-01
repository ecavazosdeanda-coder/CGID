import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../content.dart';
import '../../../glass.dart';
import '../../../audio_handler.dart';
class LecternReaderScreen extends StatefulWidget {
  final Entry entry;
  const LecternReaderScreen({super.key, required this.entry});
  @override
  State<LecternReaderScreen> createState() => _LecternReaderScreenState();
}

class _LecternReaderScreenState extends State<LecternReaderScreen> {
  double fontSize = 22.0;
  bool dark = true;
  int transposeAmount = 0;

  static const _notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  String _transposeText(String text) {
    if (transposeAmount == 0) return text;
    return text.replaceAllMapped(RegExp(r'\[([CDEFGAB][#b]?)([^\]]*)\]'), (match) {
      String note = match.group(1)!;
      String rest = match.group(2)!;
      
      if (note == 'Db') note = 'C#';
      if (note == 'Eb') note = 'D#';
      if (note == 'Gb') note = 'F#';
      if (note == 'Ab') note = 'G#';
      if (note == 'Bb') note = 'A#';

      int index = _notes.indexOf(note);
      if (index == -1) return match.group(0)!; 

      int newIndex = (index + transposeAmount) % 12;
      if (newIndex < 0) newIndex += 12;

      return '[${_notes[newIndex]}$rest]';
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable().catchError((_) {}));
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = dark ? const Color(0xff0b141a) : const Color(0xfffdfbf7);
    final textCol = dark ? Colors.white : const Color(0xff182229);
    final cardBg = dark ? const Color(0xff182229) : const Color(0xfff1ece1);
    final labelCol = dark ? const Color(0xff10b981) : const Color(0xff047857);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: dark
            ? const Color(0xff121d24)
            : const Color(0xffe8e2d5),
        foregroundColor: textCol,
        title: Text(
          widget.entry.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Transportar Tono (-)',
            icon: const Icon(Icons.exposure_minus_1),
            onPressed: () => setState(() => transposeAmount--),
          ),
          Center(
            child: Text(
              transposeAmount > 0 ? '+$transposeAmount' : '$transposeAmount',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: 'Transportar Tono (+)',
            icon: const Icon(Icons.exposure_plus_1),
            onPressed: () => setState(() => transposeAmount++),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Reducir letra',
            icon: const Icon(Icons.text_decrease),
            onPressed: fontSize > 14
                ? () => setState(() => fontSize -= 2)
                : null,
          ),
          IconButton(
            tooltip: 'Aumentar letra',
            icon: const Icon(Icons.text_increase),
            onPressed: fontSize < 42
                ? () => setState(() => fontSize += 2)
                : null,
          ),
          IconButton(
            tooltip: dark ? 'Modo claro' : 'Modo oscuro',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => setState(() => dark = !dark),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xff153b45), Color(0xff0b141a)]
                : const [Color(0xffe1eee8), Color(0xfffdfbf7)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            if (widget.entry.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.entry.subtitle,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xff94a3b8)
                        : const Color(0xff64748b),
                    fontSize: fontSize * 0.7,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final section in widget.entry.sections)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: dark
                        ? const Color(0xff233138)
                        : const Color(0xffe2d9c8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (section.label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          section.label.toUpperCase(),
                          style: TextStyle(
                            color: labelCol,
                            fontWeight: FontWeight.bold,
                            fontSize: fontSize * 0.55,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    Text(
                      _transposeText(section.text),
                      style: TextStyle(
                        color: textCol,
                        fontSize: fontSize,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
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
