import 'package:flutter/material.dart';

import '../services/score_catalog.dart';

/// Representa una porción de palabra/texto con o sin un acorde asociado.
class ChordSlice {
  final String? chord;
  final String text;

  const ChordSlice({this.chord, required this.text});

  @override
  String toString() => chord == null ? text : '[$chord]$text';
}

/// Divide un token (palabra o fragmento con acordes entre corchetes)
/// en sus sílabas o segmentos con acordes independientes.
///
/// Ejemplos:
/// - `per[G]d[D]ón.` -> [ChordSlice(text: 'per'), ChordSlice(chord: 'G', text: 'd'), ChordSlice(chord: 'D', text: 'ón.')]
/// - `[G]Quiero` -> [ChordSlice(chord: 'G', text: 'Quiero')]
/// - `[G][D]` -> [ChordSlice(chord: 'G', text: ''), ChordSlice(chord: 'D', text: '')]
/// - `a[C]fecto` -> [ChordSlice(text: 'a'), ChordSlice(chord: 'C', text: 'fecto')]
List<ChordSlice> parseTokenSlices(String token) {
  final chordRegex = RegExp(r'\[([^\]]+)\]');
  final matches = chordRegex.allMatches(token).toList();

  if (matches.isEmpty) {
    return [ChordSlice(text: token)];
  }

  final slices = <ChordSlice>[];
  var lastIndex = 0;

  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    // Texto anterior al acorde actual dentro del mismo token
    if (match.start > lastIndex) {
      slices.add(ChordSlice(text: token.substring(lastIndex, match.start)));
    }

    final chord = match.group(1)!;
    final afterChordIndex = match.end;
    final nextChordIndex =
        (i + 1 < matches.length) ? matches[i + 1].start : token.length;
    final text = token.substring(afterChordIndex, nextChordIndex);

    slices.add(ChordSlice(chord: chord, text: text));
    lastIndex = nextChordIndex;
  }

  return slices;
}

/// Renderiza una línea completa de canto con acordes alineados arriba de su sílaba.
class ChordLyricsLine extends StatelessWidget {
  final String line;
  final double fontSize;
  final Color textCol;
  final Color chordCol;
  final bool showChords;
  final int transposeAmount;
  final bool useSolfeo;

  const ChordLyricsLine({
    super.key,
    required this.line,
    required this.fontSize,
    required this.textCol,
    required this.chordCol,
    this.showChords = true,
    this.transposeAmount = 0,
    this.useSolfeo = false,
  });

  @override
  Widget build(BuildContext context) {
    if (line.trim().isEmpty) {
      return SizedBox(height: fontSize * 0.5);
    }

    // 1. Si no hay acordes activados o la línea no tiene acordes, renderiza texto limpio
    if (!showChords || !line.contains('[')) {
      final cleanText = line.replaceAll(RegExp(r'\[[^\]]+\]'), '');
      return Text(
        cleanText,
        style: TextStyle(
          color: textCol,
          fontSize: fontSize,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    // 2. Transponer acordes si el usuario cambió tono o cifrado (Do/C)
    final processedLine = (transposeAmount != 0 || useSolfeo)
        ? ChordTransposer.transposeText(line, transposeAmount, useSolfeo: useSolfeo)
        : line;

    // 3. Separar por palabras preservando estructura
    final tokens = processedLine.trim().split(RegExp(r'\s+'));

    return Wrap(
      spacing: 6.0,
      runSpacing: 10.0,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final token in tokens)
          _buildToken(token),
      ],
    );
  }

  Widget _buildToken(String token) {
    final slices = parseTokenSlices(token);
    final hasChords = slices.any((s) => s.chord != null);

    final lyricStyle = TextStyle(
      color: textCol,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );

    if (!hasChords) {
      return Text(
        token,
        style: lyricStyle,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final slice in slices)
          _buildSlice(slice, lyricStyle),
      ],
    );
  }

  Widget _buildSlice(ChordSlice slice, TextStyle lyricStyle) {
    if (slice.chord == null) {
      return Text(slice.text, style: lyricStyle);
    }

    final chordFontSize = (fontSize * 0.70).clamp(11.0, 22.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 3, right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
          decoration: BoxDecoration(
            color: chordCol.withAlpha(28),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: chordCol.withAlpha(120),
              width: 0.8,
            ),
          ),
          child: Text(
            slice.chord!,
            style: TextStyle(
              color: chordCol,
              fontSize: chordFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Text(
          slice.text.isEmpty ? ' ' : slice.text,
          style: slice.text.isEmpty
              ? lyricStyle.copyWith(color: Colors.transparent)
              : lyricStyle,
        ),
      ],
    );
  }
}

/// Renderiza un bloque completo de estrofa o coro con acordes.
class ChordLyricsBlock extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color textCol;
  final Color chordCol;
  final bool showChords;
  final int transposeAmount;
  final bool useSolfeo;

  const ChordLyricsBlock({
    super.key,
    required this.text,
    required this.fontSize,
    required this.textCol,
    required this.chordCol,
    this.showChords = true,
    this.transposeAmount = 0,
    this.useSolfeo = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          ChordLyricsLine(
            line: lines[i],
            fontSize: fontSize,
            textCol: textCol,
            chordCol: chordCol,
            showChords: showChords,
            transposeAmount: transposeAmount,
            useSolfeo: useSolfeo,
          ),
          if (i < lines.length - 1)
            SizedBox(
              height: (showChords && lines[i].contains('[')) ? 14.0 : 6.0,
            ),
        ],
      ],
    );
  }
}
