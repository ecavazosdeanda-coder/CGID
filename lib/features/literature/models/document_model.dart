enum DocumentCategory {
  puntosDeFe,
  escuelaSabatica,
  estudiosDoctrinales,
  revistasOficiales,
  otro,
}

class DocumentModel {
  final String id;
  final String title;
  final String description;
  final DocumentCategory category;
  final String? assetPath;
  final String? url;
  final String author;
  final String year;

  const DocumentModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.assetPath,
    this.url,
    required this.author,
    required this.year,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: DocumentCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => DocumentCategory.otro,
      ),
      assetPath: json['assetPath'] as String?,
      url: json['url'] as String?,
      author: json['author'] as String? ?? 'Desconocido',
      year: json['year'] as String? ?? 'N/A',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category.name,
    if (assetPath != null) 'assetPath': assetPath,
    if (url != null) 'url': url,
    'author': author,
    'year': year,
  };

  DocumentModel copyWith({
    String? id,
    String? title,
    String? description,
    DocumentCategory? category,
    String? assetPath,
    String? url,
    String? author,
    String? year,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      assetPath: assetPath ?? this.assetPath,
      url: url ?? this.url,
      author: author ?? this.author,
      year: year ?? this.year,
    );
  }
}
