import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../../../content.dart';
import 'hymn_customization_service.dart';

class DigitalScoreInfo {
  final String id;
  final List<int> sourcePages;
  final List<String> files;
  final String status;

  const DigitalScoreInfo({
    required this.id,
    required this.sourcePages,
    required this.files,
    required this.status,
  });

  factory DigitalScoreInfo.fromJson(Map<String, dynamic> json) =>
      DigitalScoreInfo(
        id: json['id'] as String,
        sourcePages: List<int>.from(json['sourcePages'] as List? ?? const []),
        files: List<String>.from(json['files'] as List? ?? const []),
        status: json['status'] as String? ?? 'needs_review',
      );

  String assetKeyFor(int index) =>
      files[index].replaceFirst(RegExp(r'^assets/assets/'), 'assets/');
}

class ChordChart {
  final String keyLabel;
  final List<List<String>> systems;

  const ChordChart({required this.keyLabel, required this.systems});

  bool get isEmpty => systems.every((system) => system.isEmpty);

  List<Section> applyToSections(List<Section> sections) {
    if (isEmpty) return sections;
    var systemIndex = 0;
    return [
      for (final section in sections)
        Section(
          section.label,
          section.text
              .split('\n')
              .map((line) {
                if (line.trim().isEmpty) return line;
                final chords = systems[systemIndex % systems.length];
                systemIndex++;
                return _applyChordsToLine(line, chords);
              })
              .join('\n'),
        ),
    ];
  }

  static String _applyChordsToLine(String line, List<String> chords) {
    if (chords.isEmpty) return line;
    final words = line.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return line;
    final prefixes = <int, List<String>>{};
    for (var index = 0; index < chords.length; index++) {
      final wordIndex = (index * words.length / chords.length).floor().clamp(
        0,
        words.length - 1,
      );
      prefixes.putIfAbsent(wordIndex, () => []).add(chords[index]);
    }
    return [
      for (var index = 0; index < words.length; index++)
        '${(prefixes[index] ?? const []).map((chord) => '[$chord]').join()}${words[index]}',
    ].join(' ');
  }
}

class ChordTransposer {
  static const _notes = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  static const _solfeo = [
    'Do',
    'Do#',
    'Re',
    'Re#',
    'Mi',
    'Fa',
    'Fa#',
    'Sol',
    'Sol#',
    'La',
    'La#',
    'Si',
  ];

  static String transposeText(
    String text,
    int semitones, {
    bool useSolfeo = false,
  }) => text.replaceAllMapped(RegExp(r'\[([A-G][#b]?)([^\]]*)\]'), (match) {
    final root = transposeNote(
      match.group(1)!,
      semitones,
      useSolfeo: useSolfeo,
    );
    var suffix = match.group(2)!;
    suffix = suffix.replaceAllMapped(RegExp(r'/([A-G][#b]?)'), (bass) {
      return '/${transposeNote(bass.group(1)!, semitones, useSolfeo: useSolfeo)}';
    });
    return '[$root$suffix]';
  });

  static String transposeNote(
    String note,
    int semitones, {
    bool useSolfeo = false,
  }) {
    const enharmonics = {
      'Db': 'C#',
      'Eb': 'D#',
      'Gb': 'F#',
      'Ab': 'G#',
      'Bb': 'A#',
    };
    final normalized = enharmonics[note] ?? note;
    final index = _notes.indexOf(normalized);
    if (index < 0) return note;
    final target = ((index + semitones) % 12 + 12) % 12;
    return useSolfeo ? _solfeo[target] : _notes[target];
  }
}

class ScoreCatalog {
  final Map<String, DigitalScoreInfo> _entries = {};
  final Map<String, Future<ChordChart?>> _chordCache = {};

  Map<String, DigitalScoreInfo> get entries => Map.unmodifiable(_entries);
  DigitalScoreInfo? operator [](String hymnId) => _entries[hymnId];
  bool contains(String hymnId) => _entries.containsKey(hymnId);

  void invalidate(String hymnId) {
    _chordCache.remove(hymnId);
  }

  Future<void> load() async {
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/scores/catalog.json'),
    ) as Map<String, dynamic>;
    _entries
      ..clear()
      ..addEntries(
        (catalog['entries'] as List? ?? const []).map((raw) {
          final entry = DigitalScoreInfo.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          return MapEntry(entry.id, entry);
        }),
      );
  }

  Future<ChordChart?> chordChartFor(String hymnId) =>
      _chordCache.putIfAbsent(hymnId, () => _loadChordChart(hymnId));

  Future<ChordChart?> _loadChordChart(String hymnId) async {
    // 1. Primero verifica si el usuario subió una partitura personalizada corregida
    final customXml = await hymnCustomizationService.getCustomScoreXml(hymnId);
    if (customXml != null && customXml.trim().isNotEmpty) {
      try {
        final document = XmlDocument.parse(customXml);
        final keyLabel = _readKey(document);
        final systems = _readChordSystems(document);
        if (systems.isNotEmpty) {
          return ChordChart(keyLabel: keyLabel, systems: systems);
        }
      } catch (_) {}
    }

    final score = _entries[hymnId];
    if (score == null || score.files.isEmpty) return null;

    final systems = <List<String>>[];
    String keyLabel = '';
    for (var fileIndex = 0; fileIndex < score.files.length; fileIndex++) {
      try {
        final data = await rootBundle.load(score.assetKeyFor(fileIndex));
        final bytes = Uint8List.sublistView(data);
        final archive = ZipDecoder().decodeBytes(bytes);
        final xmlFile = archive.files
            .where(
              (file) =>
                  file.isFile &&
                  file.name.toLowerCase().endsWith('.xml') &&
                  !file.name.startsWith('META-INF/'),
            )
            .firstOrNull;
        if (xmlFile == null) continue;
        final document = XmlDocument.parse(
          utf8.decode(xmlFile.content as List<int>),
        );
        keyLabel = keyLabel.isEmpty ? _readKey(document) : keyLabel;
        systems.addAll(_readChordSystems(document));
      } catch (_) {
        // Un archivo OCR defectuoso no debe impedir abrir el atril ni el resto
        // de las partes de la misma partitura.
      }
    }
    if (systems.isEmpty) return null;
    return ChordChart(keyLabel: keyLabel, systems: systems);
  }

  static List<List<String>> _readChordSystems(XmlDocument document) {
    final result = <List<String>>[];
    var current = <String>[];
    final firstPart = document.findAllElements('part').firstOrNull;
    if (firstPart == null) return result;
    for (final measure in firstPart.findElements('measure')) {
      final startsSystem = measure
          .findElements('print')
          .any((print) => print.getAttribute('new-system') == 'yes');
      if (startsSystem && current.isNotEmpty) {
        result.add(current);
        current = <String>[];
      }
      for (final harmony in measure.findAllElements('harmony')) {
        final chord = _readChord(harmony);
        if (chord.isNotEmpty && (current.isEmpty || current.last != chord)) {
          current.add(chord);
        }
      }
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }

  static String _readChord(XmlElement harmony) {
    final root = harmony.getElement('root');
    final step = root?.getElement('root-step')?.innerText.trim() ?? '';
    if (step.isEmpty) return '';
    final alter =
        int.tryParse(root?.getElement('root-alter')?.innerText.trim() ?? '0') ??
        0;
    final accidental = alter < 0
        ? 'b'
        : alter > 0
        ? '#'
        : '';
    final kindElement = harmony.getElement('kind');
    final explicitKind = kindElement?.getAttribute('text')?.trim() ?? '';
    final kind = explicitKind.isNotEmpty
        ? explicitKind
        : _kindSuffix(kindElement?.innerText.trim() ?? 'major');
    final bass = harmony.getElement('bass');
    final bassStep = bass?.getElement('bass-step')?.innerText.trim() ?? '';
    final bassAlter =
        int.tryParse(bass?.getElement('bass-alter')?.innerText.trim() ?? '0') ??
        0;
    final bassAccidental = bassAlter < 0
        ? 'b'
        : bassAlter > 0
        ? '#'
        : '';
    return '$step$accidental$kind${bassStep.isEmpty ? '' : '/$bassStep$bassAccidental'}';
  }

  static String _kindSuffix(String kind) {
    const suffixes = {
      'major': '',
      'minor': 'm',
      'dominant': '7',
      'major-seventh': 'maj7',
      'minor-seventh': 'm7',
      'diminished': 'dim',
      'augmented': 'aug',
      'suspended-second': 'sus2',
      'suspended-fourth': 'sus4',
      'half-diminished': 'm7b5',
      'major-sixth': '6',
      'minor-sixth': 'm6',
    };
    return suffixes[kind] ?? kind;
  }

  static String _readKey(XmlDocument document) {
    final fifths = int.tryParse(
      document.findAllElements('fifths').firstOrNull?.innerText ?? '',
    );
    if (fifths == null || fifths < -7 || fifths > 7) return '';
    const keys = [
      'Cb',
      'Gb',
      'Db',
      'Ab',
      'Eb',
      'Bb',
      'F',
      'C',
      'G',
      'D',
      'A',
      'E',
      'B',
      'F#',
      'C#',
    ];
    return keys[fifths + 7];
  }
}

final scoreCatalog = ScoreCatalog();
