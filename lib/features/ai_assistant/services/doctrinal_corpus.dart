import 'dart:convert';

import 'package:flutter/services.dart';

enum DoctrinalSourceType { faith, bible }

class DoctrinalSource {
  final String id;
  final DoctrinalSourceType type;
  final String sourceTitle;
  final String reference;
  final String text;
  final int? page;
  final String? book;
  final int? chapter;
  final int? verseStart;
  final int? verseEnd;
  final double score;

  const DoctrinalSource({
    required this.id,
    required this.type,
    required this.sourceTitle,
    required this.reference,
    required this.text,
    this.page,
    this.book,
    this.chapter,
    this.verseStart,
    this.verseEnd,
    this.score = 0,
  });

  factory DoctrinalSource.fromJson(Map<String, dynamic> json) {
    return DoctrinalSource(
      id: json['id'] as String,
      type: json['sourceType'] == 'faith'
          ? DoctrinalSourceType.faith
          : DoctrinalSourceType.bible,
      sourceTitle: json['sourceTitle'] as String,
      reference: json['reference'] as String,
      text: json['text'] as String,
      page: json['page'] as int?,
      book: json['book'] as String?,
      chapter: int.tryParse('${json['chapter'] ?? ''}'),
      verseStart: int.tryParse('${json['verseStart'] ?? ''}'),
      verseEnd: int.tryParse('${json['verseEnd'] ?? ''}'),
    );
  }

  DoctrinalSource withScore(double value) => DoctrinalSource(
    id: id,
    type: type,
    sourceTitle: sourceTitle,
    reference: reference,
    text: text,
    page: page,
    book: book,
    chapter: chapter,
    verseStart: verseStart,
    verseEnd: verseEnd,
    score: value,
  );

  String get citation {
    final pageLabel = page == null ? '' : ', p. $page';
    return '$reference ($sourceTitle$pageLabel)';
  }
}

class DoctrinalCorpusStats {
  final int faithDocuments;
  final int bibleDocuments;

  const DoctrinalCorpusStats({
    required this.faithDocuments,
    required this.bibleDocuments,
  });

  int get totalDocuments => faithDocuments + bibleDocuments;
}

class DoctrinalCorpus {
  static const assetPath = 'assets/data/doctrinal_corpus.json';
  static const _stopWords = {
    'a',
    'al',
    'algo',
    'como',
    'con',
    'cual',
    'de',
    'del',
    'donde',
    'el',
    'ella',
    'en',
    'es',
    'esta',
    'este',
    'la',
    'las',
    'lo',
    'los',
    'me',
    'para',
    'por',
    'que',
    'se',
    'segun',
    'sobre',
    'su',
    'sus',
    'un',
    'una',
    'y',
  };

  List<DoctrinalSource>? _documents;
  List<Map<String, int>>? _termFrequencies;

  DoctrinalCorpus();

  DoctrinalCorpus.fromDocuments(List<DoctrinalSource> documents) {
    _documents = List.unmodifiable(documents);
    _buildIndex();
  }

  bool get isLoaded => _documents != null;

  DoctrinalCorpusStats get stats {
    final documents = _documents ?? const <DoctrinalSource>[];
    return DoctrinalCorpusStats(
      faithDocuments: documents
          .where((item) => item.type == DoctrinalSourceType.faith)
          .length,
      bibleDocuments: documents
          .where((item) => item.type == DoctrinalSourceType.bible)
          .length,
    );
  }

  Future<void> load() async {
    if (isLoaded) return;
    final jsonString = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    if (decoded['schemaVersion'] != 1) {
      throw const FormatException('Versión de corpus doctrinal no soportada.');
    }
    final rawDocuments = decoded['documents'] as List<dynamic>? ?? const [];
    _documents = List.unmodifiable(
      rawDocuments.map(
        (item) =>
            DoctrinalSource.fromJson(Map<String, dynamic>.from(item as Map)),
      ),
    );
    _buildIndex();
  }

  List<DoctrinalSource> search(String query, {int limit = 6}) {
    if (!isLoaded || query.trim().isEmpty || limit <= 0) return const [];
    final queryTokens = _tokenize(query).toSet();
    if (queryTokens.isEmpty) return const [];

    final documents = _documents!;
    final frequencies = _termFrequencies!;
    final normalizedQuery = _normalize(query);
    final scriptureReference = _parseScriptureReference(query);
    final scored = <DoctrinalSource>[];

    for (var index = 0; index < documents.length; index++) {
      final document = documents[index];
      final terms = frequencies[index];
      var score = 0.0;
      for (final term in queryTokens) {
        final frequency = terms[term] ?? 0;
        if (frequency > 0) {
          score += 2.0 + frequency.clamp(0, 4);
        }
        if (_normalize(document.reference).contains(term)) score += 3.5;
      }
      final normalizedReference = _normalize(document.reference);
      if (normalizedQuery.length >= 4 &&
          normalizedReference.contains(normalizedQuery)) {
        score += 20;
      }
      if (_matchesScriptureReference(document, scriptureReference)) {
        score += 100;
      }
      if (document.type == DoctrinalSourceType.faith && score > 0) {
        score *= 1.15;
      }
      if (score >= 3) scored.add(document.withScore(score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final selected = <DoctrinalSource>[];
    var bibleCount = 0;
    var faithCount = 0;
    for (final item in scored) {
      if (selected.length >= limit) break;
      if (item.type == DoctrinalSourceType.bible) {
        if (bibleCount >= 4) continue;
        bibleCount++;
      } else {
        if (faithCount >= 3) continue;
        faithCount++;
      }
      selected.add(item);
    }
    return selected;
  }

  void _buildIndex() {
    _termFrequencies = _documents!
        .map((document) {
          final counts = <String, int>{};
          final searchable =
              '${document.reference} ${document.sourceTitle} ${document.text}';
          for (final term in _tokenize(searchable)) {
            counts.update(term, (value) => value + 1, ifAbsent: () => 1);
          }
          return counts;
        })
        .toList(growable: false);
  }

  static Iterable<String> _tokenize(String value) sync* {
    for (final match in RegExp(r'[a-z0-9]+').allMatches(_normalize(value))) {
      final token = match.group(0)!;
      if (token.length > 1 && !_stopWords.contains(token)) yield token;
    }
  }

  static _ScriptureReference? _parseScriptureReference(String query) {
    final normalized = _normalize(query);
    final match = RegExp(
      r'\b((?:[1-3]\s+)?[a-z]+(?:\s+[a-z]+)?)\s+(\d{1,3})\s+(\d{1,3})\b',
    ).firstMatch(normalized);
    if (match == null) return null;
    return _ScriptureReference(
      book: match.group(1)!,
      chapter: int.parse(match.group(2)!),
      verse: int.parse(match.group(3)!),
    );
  }

  static bool _matchesScriptureReference(
    DoctrinalSource document,
    _ScriptureReference? reference,
  ) {
    if (reference == null ||
        document.type != DoctrinalSourceType.bible ||
        document.book == null ||
        document.chapter != reference.chapter ||
        document.verseStart == null ||
        document.verseEnd == null) {
      return false;
    }
    final documentBook = _normalize(document.book!);
    final sameBook =
        documentBook == reference.book ||
        documentBook.endsWith(' ${reference.book}') ||
        reference.book.endsWith(' $documentBook');
    return sameBook &&
        reference.verse >= document.verseStart! &&
        reference.verse <= document.verseEnd!;
  }

  static String _normalize(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      '�': '',
    };
    replacements.forEach((source, target) {
      result = result.replaceAll(source, target);
    });
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }
}

class _ScriptureReference {
  final String book;
  final int chapter;
  final int verse;

  const _ScriptureReference({
    required this.book,
    required this.chapter,
    required this.verse,
  });
}
