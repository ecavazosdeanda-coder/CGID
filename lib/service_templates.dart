import 'content.dart';

class ServiceTemplate {
  final String id;
  final String title;
  final String iconKey;
  final List<Entry> entries;

  const ServiceTemplate({
    required this.id,
    required this.title,
    required this.iconKey,
    required this.entries,
  });

  ServiceTemplate copyWith({
    String? title,
    String? iconKey,
    List<Entry>? entries,
  }) => ServiceTemplate(
    id: id,
    title: title ?? this.title,
    iconKey: iconKey ?? this.iconKey,
    entries: entries ?? this.entries,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'iconKey': iconKey,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory ServiceTemplate.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? '').trim();
    if (title.isEmpty) throw const FormatException('Plantilla sin título.');
    return ServiceTemplate(
      id: json['id'] as String? ?? 'template-${title.hashCode}',
      title: title,
      iconKey: json['iconKey'] as String? ?? 'church',
      entries: [
        for (final entry in json['entries'] as List? ?? const [])
          Entry.fromJson(Map<String, dynamic>.from(entry as Map)),
      ],
    );
  }
}
