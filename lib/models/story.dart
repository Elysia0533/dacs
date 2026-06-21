class Story {
  final String id;
  final String title;
  final String titleEng;
  final String content;
  final String contentEng;
  final String description;
  final String author;
  final List<String> genres;
  final int totalChapters;
  final int currentChapter;
  final int savedChapterIndex;
  final String iconUrl;
  final String localPath;
  final bool isLocal;
  final String driveFileId;
  final bool isFromDrive;
  final String fileType;
  final double rating;       // Điểm trung bình (0.0 - 5.0)
  final int ratingCount;     // Tổng số lượt đánh giá

  Story({
    required this.id,
    required this.title,
    this.content = "",
    this.titleEng = "",
    this.contentEng = "",
    this.description = "",
    this.author = "",
    this.genres = const [],
    this.totalChapters = 1,
    this.currentChapter = 1,
    this.savedChapterIndex = 0,
    this.iconUrl = "",
    this.localPath = "",
    this.isLocal = false,
    this.driveFileId = "",
    this.isFromDrive = false,
    this.fileType = "",
    this.rating = 0.0,
    this.ratingCount = 0,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      titleEng: json['titleEng'] ?? '',
      contentEng: json['contentEng'] ?? '',
      description: json['description'] ?? '',
      author: json['author'] ?? '',
      genres:
          (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      totalChapters: json['totalChapters'] ?? 1,
      currentChapter: json['currentChapter'] ?? 1,
      savedChapterIndex: json['savedChapterIndex'] ?? 0,
      iconUrl: json['iconUrl'] ?? '',
      localPath: json['localPath'] ?? '',
      isLocal: json['isLocal'] ?? false,
      driveFileId: json['driveFileId'] ?? '',
      isFromDrive: json['isFromDrive'] ?? false,
      fileType: json['fileType'] ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: json['ratingCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'titleEng': titleEng,
      'contentEng': contentEng,
      'description': description,
      'author': author,
      'genres': genres,
      'totalChapters': totalChapters,
      'currentChapter': currentChapter,
      'savedChapterIndex': savedChapterIndex,
      'iconUrl': iconUrl,
      'localPath': localPath,
      'isLocal': isLocal,
      'driveFileId': driveFileId,
      'isFromDrive': isFromDrive,
      'fileType': fileType,
      'rating': rating,
      'ratingCount': ratingCount,
    };
  }

  Story copyWith({
    String? id,
    String? title,
    String? titleEng,
    String? content,
    String? contentEng,
    String? description,
    String? author,
    List<String>? genres,
    int? totalChapters,
    int? currentChapter,
    int? savedChapterIndex,
    String? iconUrl,
    String? localPath,
    bool? isLocal,
    String? driveFileId,
    bool? isFromDrive,
    String? fileType,
    double? rating,
    int? ratingCount,
  }) {
    return Story(
      id: id ?? this.id,
      title: title ?? this.title,
      titleEng: titleEng ?? this.titleEng,
      content: content ?? this.content,
      contentEng: contentEng ?? this.contentEng,
      description: description ?? this.description,
      author: author ?? this.author,
      genres: genres ?? this.genres,
      totalChapters: totalChapters ?? this.totalChapters,
      currentChapter: currentChapter ?? this.currentChapter,
      savedChapterIndex: savedChapterIndex ?? this.savedChapterIndex,
      iconUrl: iconUrl ?? this.iconUrl,
      localPath: localPath ?? this.localPath,
      isLocal: isLocal ?? this.isLocal,
      driveFileId: driveFileId ?? this.driveFileId,
      isFromDrive: isFromDrive ?? this.isFromDrive,
      fileType: fileType ?? this.fileType,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
    );
  }
}
