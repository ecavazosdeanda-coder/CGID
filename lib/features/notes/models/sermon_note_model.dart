class SermonNote {
  final String id;
  final String title;
  final String preacher;
  final String churchName;
  final DateTime date;
  final String bibleReference;
  final String hymnReference;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;

  const SermonNote({
    required this.id,
    required this.title,
    this.preacher = '',
    this.churchName = '',
    required this.date,
    this.bibleReference = '',
    this.hymnReference = '',
    this.content = '',
    this.tags = const [],
    required this.updatedAt,
  });

  SermonNote copyWith({
    String? id,
    String? title,
    String? preacher,
    String? churchName,
    DateTime? date,
    String? bibleReference,
    String? hymnReference,
    String? content,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return SermonNote(
      id: id ?? this.id,
      title: title ?? this.title,
      preacher: preacher ?? this.preacher,
      churchName: churchName ?? this.churchName,
      date: date ?? this.date,
      bibleReference: bibleReference ?? this.bibleReference,
      hymnReference: hymnReference ?? this.hymnReference,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'preacher': preacher,
    'churchName': churchName,
    'date': date.toIso8601String(),
    'bibleReference': bibleReference,
    'hymnReference': hymnReference,
    'content': content,
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SermonNote.fromJson(Map<String, dynamic> json) => SermonNote(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: json['title'] as String? ?? 'Nota de Culto',
    preacher: json['preacher'] as String? ?? '',
    churchName: json['churchName'] as String? ?? '',
    date: json['date'] != null
        ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
        : DateTime.now(),
    bibleReference: json['bibleReference'] as String? ?? '',
    hymnReference: json['hymnReference'] as String? ?? '',
    content: json['content'] as String? ?? '',
    tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  String toShareableText() {
    final buffer = StringBuffer();
    buffer.writeln('📖 *${title.trim()}*');
    if (preacher.trim().isNotEmpty) {
      buffer.writeln('👤 *Predicador:* ${preacher.trim()}');
    }
    if (churchName.trim().isNotEmpty) {
      buffer.writeln('🏛️ *Congregación:* ${churchName.trim()}');
    }
    buffer.writeln('📅 *Fecha:* ${date.day}/${date.month}/${date.year}');
    if (bibleReference.trim().isNotEmpty) {
      buffer.writeln('📜 *Texto Bíblico:* ${bibleReference.trim()}');
    }
    if (hymnReference.trim().isNotEmpty) {
      buffer.writeln('🎵 *Himno:* ${hymnReference.trim()}');
    }
    buffer.writeln('');
    buffer.writeln('📝 *Notas y Bosquejo:*');
    buffer.writeln(content.trim());
    buffer.writeln('');
    buffer.writeln('— Conferencia General de la Iglesia de Dios (CGDI)');
    return buffer.toString();
  }
}
