import 'dart:convert';

import 'package:flutter/services.dart';

String normalized(String value) {
  const a = 'áéíóúüñ';
  const b = 'aeiouun';
  var result = value.toLowerCase();
  for (var i = 0; i < a.length; i++) {
    result = result.replaceAll(a[i], b[i]);
  }
  return result;
}

class Section {
  final String label, text;
  const Section(this.label, this.text);
  Map<String, dynamic> toJson() => {'label': label, 'text': text};
  factory Section.fromJson(Map<String, dynamic> j) =>
      Section(j['label'], j['text']);
}

/// Una responsabilidad concreta dentro de un culto. No representa el nivel de
/// acceso permanente de la cuenta: la misma persona puede presidir un culto y
/// predicar en otro.
class ServiceAssignment {
  final String role;
  final String displayName;
  final bool showInBulletin;

  const ServiceAssignment({
    required this.role,
    required this.displayName,
    this.showInBulletin = true,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'displayName': displayName,
    'showInBulletin': showInBulletin,
  };

  factory ServiceAssignment.fromJson(Map<String, dynamic> json) =>
      ServiceAssignment(
        role: json['role'] as String? ?? 'otro',
        displayName: json['displayName'] as String? ?? '',
        showInBulletin: json['showInBulletin'] as bool? ?? true,
      );

  String get roleLabel {
    switch (role) {
      case 'presidente':
        return 'Presidente';
      case 'predicador':
        return 'Predicador';
      case 'lector':
        return 'Lector';
      case 'oracion':
        return 'Oración';
      case 'musica':
        return 'Música';
      case 'multimedia':
        return 'Multimedia';
      default:
        return 'Responsable';
    }
  }
}

class ServicePlanMetadata {
  final String serviceDate;
  final List<ServiceAssignment> assignments;

  const ServicePlanMetadata({
    this.serviceDate = '',
    this.assignments = const [],
  });

  String personFor(String role) => assignments
      .where((assignment) => assignment.role == role)
      .map((assignment) => assignment.displayName.trim())
      .firstWhere((name) => name.isNotEmpty, orElse: () => '');

  String get dateLabel {
    if (serviceDate.isEmpty) return '';
    final date = DateTime.tryParse(serviceDate);
    if (date == null) return serviceDate;
    return '${date.day}/${date.month}/${date.year}';
  }

  Map<String, dynamic> toJson() => {
    'serviceDate': serviceDate,
    'assignments': assignments
        .map((assignment) => assignment.toJson())
        .toList(),
  };

  factory ServicePlanMetadata.fromJson(Map<String, dynamic> json) =>
      ServicePlanMetadata(
        serviceDate: json['serviceDate'] as String? ?? '',
        assignments: [
          for (final assignment in json['assignments'] as List? ?? const [])
            ServiceAssignment.fromJson(
              Map<String, dynamic>.from(assignment as Map),
            ),
        ],
      );
}

class Entry {
  final String id, title, subtitle, pdf;
  final int page;
  final List<Section> sections;
  final List<String> mediaIds;
  final String notes;
  final List<ServiceAssignment> assignments;
  const Entry({
    required this.id,
    required this.title,
    required this.sections,
    this.subtitle = '',
    this.pdf = '',
    this.page = 1,
    this.mediaIds = const [],
    this.notes = '',
    this.assignments = const [],
  });

  Entry copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? pdf,
    int? page,
    List<Section>? sections,
    List<String>? mediaIds,
    String? notes,
    List<ServiceAssignment>? assignments,
  }) => Entry(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    pdf: pdf ?? this.pdf,
    page: page ?? this.page,
    sections: sections ?? this.sections,
    mediaIds: mediaIds ?? this.mediaIds,
    notes: notes ?? this.notes,
    assignments: assignments ?? this.assignments,
  );

  String get searchable =>
      normalized('$title $subtitle ${sections.map((s) => s.text).join(' ')}');

  /// Las herramientas de acordes pertenecen exclusivamente al contenido
  /// musical. Los himnos oficiales usan IDs `h...`; los himnos especiales
  /// se identifican por su subtítulo al convertirlos en [Entry].
  bool get supportsChordTools =>
      id.startsWith('h') || subtitle.startsWith('Himno Local');

  // Keep verse numbers for display/projection, but never speak their prefixes.
  String get spokenText => sections
      .map(
        (s) => id.startsWith('b')
            ? s.text.replaceFirst(RegExp(r'^\s*\d+\s+'), '')
            : s.text,
      )
      .join('\n');
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'pdf': pdf,
    'page': page,
    'sections': sections.map((s) => s.toJson()).toList(),
    'mediaIds': mediaIds,
    'notes': notes,
    'assignments': assignments
        .map((assignment) => assignment.toJson())
        .toList(),
  };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'],
    title: j['title'],
    subtitle: j['subtitle'] ?? '',
    pdf: j['pdf'] ?? '',
    page: j['page'] ?? 1,
    mediaIds: List<String>.from(j['mediaIds'] ?? []),
    notes: j['notes'] ?? '',
    assignments: [
      for (final assignment in j['assignments'] as List? ?? const [])
        ServiceAssignment.fromJson(
          Map<String, dynamic>.from(assignment as Map),
        ),
    ],
    sections: (j['sections'] as List)
        .map((s) => Section.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
}

class BibleCrossReference {
  final int book, chapter, start, end, votes;
  const BibleCrossReference(
    this.book,
    this.chapter,
    this.start,
    this.end,
    this.votes,
  );
}

class Library {
  final List<Entry> hymns, faith;
  final List<dynamic> bible;
  final String notice;
  final List<dynamic> warnings;
  final String bibleEdition;
  final Map<String, List<BibleCrossReference>> crossReferences;
  Library(
    this.hymns,
    this.faith,
    this.bible,
    this.notice,
    this.warnings, [
    this.bibleEdition = 'Santa Biblia · Reina-Valera 1909',
    this.crossReferences = const {},
  ]);
  static Future<Library> load() async {
    final audioReport = jsonDecode(
      await rootBundle.loadString('assets/audio/import_report.json'),
    );
    final j = jsonDecode(
      await rootBundle.loadString('assets/library_content_v6.json'),
    );
    final crossJson = jsonDecode(
      await rootBundle.loadString('assets/cross_references.json'),
    );
    final crossReferences = <String, List<BibleCrossReference>>{
      for (final item in (crossJson['entries'] as Map<String, dynamic>).entries)
        item.key: [
          for (final raw in item.value)
            BibleCrossReference(
              raw[0] as int,
              raw[1] as int,
              raw[2] as int,
              raw[3] as int,
              raw[4] as int,
            ),
        ],
    };
    return Library(
      [
        for (final h in j['hymns'])
          Entry(
            id: h['id'],
            title: '${h['number']}. ${h['title']}',
            subtitle: '${h['category']} · ${h['credits']}',
            pdf: 'himnario.pdf',
            page: h['page'],
            sections: [
              for (final s in h['sections']) Section(s['label'], s['text']),
            ],
          ),
        for (final audio in audioReport['unmatched'])
          Entry(
            id: audio['id'],
            title: audio['title'],
            subtitle: 'Grabación adicional · Letra pendiente de vincular',
            sections: const [],
          ),
      ],
      [
        for (final f in j['faith'])
          Entry(
            id: f['id'],
            title: '${f['number']}. ${f['title']}',
            subtitle: 'Puntos de fe · Edición de 1977',
            pdf: 'fe.pdf',
            page: f['page'],
            sections: [Section('Texto', f['text'])],
          ),
      ],
      j['bible'],
      j['notice'],
      j['warnings'],
      j['bibleEdition'] ?? 'Santa Biblia · Reina-Valera 1909',
      crossReferences,
    );
  }

  Entry passage(int b, int c, int start, int end) {
    final book = bible[b];
    final verses = (book['chapters'][c]['verses'] as List)
        .where((v) => v['number'] >= start && v['number'] <= end)
        .toList();
    return Entry(
      id: 'b$b:$c:$start:$end',
      title: '${book['name']} ${c + 1}:$start${end == start ? '' : '-$end'}',
      subtitle: bibleEdition,
      pdf: 'biblia.pdf',
      page: verses.isEmpty ? 1 : verses.first['page'],
      sections: [
        for (final v in verses)
          Section('Versículo ${v['number']}', '${v['number']} ${v['text']}'),
      ],
    );
  }

  List<BibleCrossReference> concordance(int book, int chapter, int verse) =>
      crossReferences['$book:$chapter:$verse'] ?? const [];

  List<Entry> references(String text) {
    final aliases = <String, int>{
      for (var i = 0; i < bible.length; i++) normalized(bible[i]['name']): i,
      'salmo': 18,
      'ruth': 7,
      'esther': 16,
      'ecclesiastes': 20,
      'cantar de los cantares': 21,
      'h aggeo': 36,
      'haggeo': 36,
    };
    final keys = aliases.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp(
      '(${keys.map(RegExp.escape).join('|')})\\s+(\\d+)\\s*[:.]\\s*(\\d+(?:\\s*[-,]\\s*\\d+)*)',
    );
    final result = <String, Entry>{};
    for (final m in pattern.allMatches(
      normalized(text).replaceAll('\n', ' '),
    )) {
      final b = aliases[m[1]]!;
      final c = int.parse(m[2]!) - 1;
      if (c < 0 || c >= (bible[b]['chapters'] as List).length) continue;
      final last = (bible[b]['chapters'][c]['verses'] as List).length;
      for (final part in m[3]!.split(',')) {
        final range = part.split('-').map((n) => int.parse(n.trim())).toList();
        final start = range.first, end = range.last;
        if (start < 1 || end < start || end > last) continue;
        final e = passage(b, c, start, end);
        result[e.id] = e;
      }
    }
    return result.values.toList();
  }
}

class SlideData {
  final String title, label, text;
  final String? mediaId, imageData;
  const SlideData(
    this.title,
    this.label,
    this.text, {
    this.mediaId,
    this.imageData,
  });
  Map<String, dynamic> toJson() => {
    'title': title,
    'label': label,
    'text': text,
    'mediaId': mediaId,
    'imageData': imageData,
  };
  factory SlideData.fromJson(Map<String, dynamic> j) => SlideData(
    j['title'] ?? '',
    j['label'] ?? '',
    j['text'] ?? '',
    mediaId: j['mediaId'],
    imageData: j['imageData'],
  );
}

// Preserve words, wrap at spaces and split before reducing type size.
List<SlideData> makeSlides(
  Entry entry, {
  int maxLines = 4,
  int columns = 38,
  bool repeatChorus = true,
}) {
  if (entry.mediaIds.isNotEmpty) {
    return [
      for (var i = 0; i < entry.mediaIds.length; i++)
        SlideData(
          entry.title,
          'Página ${i + 1}',
          '',
          mediaId: entry.mediaIds[i],
        ),
    ];
  }
  if (entry.sections.isEmpty) {
    return [SlideData('', entry.subtitle, entry.title)];
  }
  final result = <SlideData>[];
  final chorus = entry.sections
      .where((s) => s.label.toLowerCase().startsWith('coro'))
      .firstOrNull;
  final ordered = <Section>[];
  if (repeatChorus && chorus != null) {
    var activeChorus = chorus;
    for (var i = 0; i < entry.sections.length; i++) {
      final s = entry.sections[i];
      if (s.label.toLowerCase().startsWith('coro')) {
        activeChorus = s;
        ordered.add(s);
      } else {
        ordered.add(s);
        final next = i + 1 < entry.sections.length
            ? entry.sections[i + 1]
            : null;
        if (next == null || !next.label.toLowerCase().startsWith('coro')) {
          ordered.add(activeChorus);
        }
      }
    }
    if (ordered.isEmpty) {
      ordered.addAll(entry.sections);
    }
  } else {
    ordered.addAll(entry.sections);
  }
  for (final s in ordered) {
    final rows = <String>[];
    for (final line in s.text.split('\n')) {
      var row = '';
      for (final word
          in line.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
        if (row.isNotEmpty && row.length + word.length + 1 > columns) {
          rows.add(row);
          row = word;
        } else {
          row = row.isEmpty ? word : '$row $word';
        }
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    for (var i = 0; i < rows.length; i += maxLines) {
      result.add(
        SlideData(entry.title, s.label, rows.skip(i).take(maxLines).join('\n')),
      );
    }
  }
  return result;
}
