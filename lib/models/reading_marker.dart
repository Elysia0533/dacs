class ReadingMarker {
  final String id;
  final String storyId;
  final String storyTitle;
  final String chapterTitle;
  final String iconUrl;
  final String driveFileId;
  final String fileType;
  final String localPath;
  final int chapterIndex;
  final double scrollOffset;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReadingMarker({
    required this.id,
    required this.storyId,
    required this.storyTitle,
    this.chapterTitle = '',
    this.iconUrl = '',
    this.driveFileId = '',
    this.fileType = '',
    this.localPath = '',
    this.chapterIndex = 0,
    this.scrollOffset = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReadingMarker.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ReadingMarker(
      id: json['id']?.toString() ?? '',
      storyId: json['storyId']?.toString() ?? '',
      storyTitle: json['storyTitle']?.toString() ?? '',
      chapterTitle: json['chapterTitle']?.toString() ?? '',
      iconUrl: json['iconUrl']?.toString() ?? '',
      driveFileId: json['driveFileId']?.toString() ?? '',
      fileType: json['fileType']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      chapterIndex: _readInt(json['chapterIndex']),
      scrollOffset: _readDouble(json['scrollOffset']),
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'storyId': storyId,
      'storyTitle': storyTitle,
      'chapterTitle': chapterTitle,
      'iconUrl': iconUrl,
      'driveFileId': driveFileId,
      'fileType': fileType,
      'localPath': localPath,
      'chapterIndex': chapterIndex,
      'scrollOffset': scrollOffset,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  ReadingMarker copyWith({
    String? id,
    String? storyId,
    String? storyTitle,
    String? chapterTitle,
    String? iconUrl,
    String? driveFileId,
    String? fileType,
    String? localPath,
    int? chapterIndex,
    double? scrollOffset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReadingMarker(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      storyTitle: storyTitle ?? this.storyTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      iconUrl: iconUrl ?? this.iconUrl,
      driveFileId: driveFileId ?? this.driveFileId,
      fileType: fileType ?? this.fileType,
      localPath: localPath ?? this.localPath,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _readDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
