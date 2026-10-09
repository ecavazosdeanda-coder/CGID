class SpecialHymn {
  final String id;
  final String title;
  final String churchId;
  final String? eventContext;
  final String? lyrics;
  final String? chords;
  final String? audioStorageUrl;
  final String? sheetMusicStorageUrl;
  final DateTime createdAt;
  final String uploadedBy;

  const SpecialHymn({
    required this.id,
    required this.title,
    required this.churchId,
    this.eventContext,
    this.lyrics,
    this.chords,
    this.audioStorageUrl,
    this.sheetMusicStorageUrl,
    required this.createdAt,
    required this.uploadedBy,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'churchId': churchId,
    'eventContext': eventContext,
    'lyrics': lyrics,
    'chords': chords,
    'audioStorageUrl': audioStorageUrl,
    'sheetMusicStorageUrl': sheetMusicStorageUrl,
    'createdAt': createdAt.toIso8601String(),
    'uploadedBy': uploadedBy,
  };

  factory SpecialHymn.fromJson(Map<String, dynamic> json) => SpecialHymn(
    id: json['id'] as String,
    title: json['title'] as String,
    churchId: json['churchId'] as String,
    eventContext: json['eventContext'] as String?,
    lyrics: json['lyrics'] as String?,
    chords: json['chords'] as String?,
    audioStorageUrl: json['audioStorageUrl'] as String?,
    sheetMusicStorageUrl: json['sheetMusicStorageUrl'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    uploadedBy: json['uploadedBy'] as String,
  );
}
