import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/story.dart';

class GoogleDriveService {
  static const String apiKey = String.fromEnvironment('GOOGLE_DRIVE_API_KEY');
  static const String defaultFolderUrl = String.fromEnvironment(
    'GOOGLE_DRIVE_FOLDER_URL',
  );
  static const String defaultFolderUrls = String.fromEnvironment(
    'GOOGLE_DRIVE_FOLDER_URLS',
  );
  static const List<String> demoFolderUrls = [
    'https://drive.google.com/drive/folders/1JqHqueAhOcybtFQixX1PTypmq0MB7Mrx?usp=sharing',
    'https://drive.google.com/drive/folders/135QOQhnFAvSHoqbnr8aZmXbuFnZ3DBJJ?usp=drive_link',
    'https://drive.google.com/drive/folders/1h8xikg-VhsrSW-J5UBb5xLstn03L86tU?usp=drive_link',
    'https://drive.google.com/drive/folders/1X0mttYF0vCqT2ky1MQxpwPufksQoenj9?usp=drive_link',
    'https://drive.google.com/drive/folders/1JdFVB8f_7j6KvWb4DJIZsmFWZmokuSFh',
    'https://drive.google.com/drive/folders/10qaC4oMuVDtc6i8reqOEgGYf9MkgeS1V',
  ];

  static const String _folderMimeType = 'application/vnd.google-apps.folder';
  static const Set<String> _supportedExtensions = {'epub', 'pdf', 'txt'};
  static const int _maxScanDepth = 4;

  static String? extractFolderId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('http') && !trimmed.contains('/')) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.pathSegments.contains('folders')) {
      final index = uri.pathSegments.indexOf('folders');
      if (index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }

    final id = uri.queryParameters['id'];
    if (id != null && id.trim().isNotEmpty) return id.trim();

    return null;
  }

  static Future<List<Story>> fetchStoriesFromConfiguredFolder() async {
    final folderUrls = _configuredFolderUrls();
    if (folderUrls.isEmpty) {
      throw Exception(
        'Thiếu GOOGLE_DRIVE_FOLDER_URL hoặc GOOGLE_DRIVE_FOLDER_URLS. Hãy truyền link thư mục Drive bằng --dart-define.',
      );
    }
    return fetchStoriesFromFolders(folderUrls);
  }

  static Future<List<Story>> fetchStoriesFromFolders(
    Iterable<String> folderUrls,
  ) async {
    _ensureApiKey();

    final inputs = folderUrls
        .map((folderUrl) => folderUrl.trim())
        .where((folderUrl) => folderUrl.isNotEmpty)
        .toList();
    if (inputs.isEmpty) {
      throw Exception('Vui lòng nhập ít nhất một link hoặc ID thư mục Drive.');
    }

    final results = await Future.wait(
      inputs.map((folderUrl) async {
        try {
          return _FolderScanResult(
            stories: await fetchStoriesFromFolder(folderUrl),
          );
        } catch (e) {
          return _FolderScanResult(error: '$folderUrl: $e');
        }
      }),
    );

    final stories = _dedupeStories([
      for (final result in results) ...result.stories,
    ]);
    final errors = [
      for (final result in results)
        if (result.error != null) result.error!,
    ];
    if (stories.isEmpty && errors.isNotEmpty) {
      throw Exception(errors.join('\n'));
    }
    return stories;
  }

  static Future<List<Story>> fetchStoriesFromFolder(String folderUrl) async {
    final folderId = extractFolderId(folderUrl);
    if (folderId == null) {
      throw Exception('URL hoặc ID thư mục Google Drive không hợp lệ');
    }
    _ensureApiKey();

    final rootFiles = await _listChildren(folderId);

    final catalogFile = _findNamedFile(rootFiles, 'catalog.json');
    if (catalogFile != null) {
      try {
        final catalogStories = await _readCatalogStories(catalogFile.id);
        return catalogStories;
      } catch (_) {}
    }

    return _scanFolderStories(rootFiles);
  }

  static List<String> parseFolderInputs(String value) {
    return value
        .split(RegExp(r'[\n,;|]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<String> _configuredFolderUrls() {
    return {
      ...demoFolderUrls,
      ...parseFolderInputs(defaultFolderUrls),
      ...parseFolderInputs(defaultFolderUrl),
    }.toList();
  }

  static List<Story> _dedupeStories(List<Story> stories) {
    final seen = <String>{};
    final result = <Story>[];

    for (final story in stories) {
      final key = story.driveFileId.isNotEmpty ? story.driveFileId : story.id;
      if (key.isEmpty || seen.add(key)) {
        result.add(story);
      }
    }

    return result;
  }

  static Future<List<Story>> _readCatalogStories(String fileId) async {
    final bytes = await downloadFileBytes(fileId);
    final decoded = json.decode(utf8.decode(bytes));

    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['stories'] is List) {
      items = decoded['stories'] as List<dynamic>;
    } else {
      throw Exception('catalog.json phải là mảng hoặc có field stories');
    }

    return items
        .whereType<Map>()
        .map((item) => _storyFromCatalogMap(Map<String, dynamic>.from(item)))
        .whereType<Story>()
        .toList();
  }

  static Story? _storyFromCatalogMap(Map<String, dynamic> map) {
    final chapterOrder = _readStringList(map['chapterOrder']);
    final driveFileId =
        _readString(map['driveFileId']) ??
        _readString(map['fileId']) ??
        (chapterOrder.isNotEmpty ? chapterOrder.first : null);
    if (driveFileId == null || driveFileId.isEmpty) return null;

    final coverFileId =
        _readString(map['coverFileId']) ?? _readString(map['coverId']);
    final iconUrl =
        _readString(map['iconUrl']) ??
        _readString(map['coverUrl']) ??
        (coverFileId == null ? '' : getCoverImageUrl(coverFileId));

    final title = _readString(map['title']) ?? _cleanFileName(driveFileId);
    final storyId = _readString(map['id']) ?? driveFileId;
    final totalChapters =
        _readInt(map['totalChapters']) ??
        (chapterOrder.isNotEmpty ? chapterOrder.length : 1);
    final fileType =
        _readString(map['fileType']) ?? _readString(map['type']) ?? '';

    return Story(
      id: storyId,
      title: title,
      titleEng: _readString(map['titleEng']) ?? '',
      description: _readString(map['description']) ?? '',
      author: _readString(map['author']) ?? '',
      genres: _readStringList(map['genres']),
      totalChapters: totalChapters < 1 ? 1 : totalChapters,
      iconUrl: iconUrl,
      driveFileId: driveFileId,
      isFromDrive: true,
      isLocal: false,
      fileType: fileType.toLowerCase(),
    );
  }

  static Future<List<Story>> _scanFolderStories(
    List<_DriveFile> rootFiles, {
    int depth = 0,
  }) async {
    final results = await Future.wait(
      rootFiles.map((item) => _scanDriveItem(item, depth)),
    );
    return _dedupeStories([for (final result in results) ...result]);
  }

  static Future<List<Story>> _scanDriveItem(_DriveFile item, int depth) async {
    if (!item.isFolder) {
      return item.isStoryFile ? [_storyFromDriveFile(item)] : const [];
    }

    final stories = <Story>[];
    final children = await _listChildren(item.id);
    final catalogFile = _findNamedFile(children, 'catalog.json');
    if (catalogFile != null) {
      try {
        stories.addAll(await _readCatalogStories(catalogFile.id));
      } catch (_) {}
    }

    final ebookFiles = children.where((file) => file.isStoryFile).toList();
    final info = await _readOptionalInfoJson(children);
    final coverFile = _findCoverFile(children);

    if (ebookFiles.isNotEmpty) {
      final folderTitle = _readString(info['title']) ?? item.name;
      for (final file in ebookFiles) {
        final hasMultipleVolumes = ebookFiles.length > 1;
        final cleanFileName = _cleanFileName(file.name);
        final displayTitle = hasMultipleVolumes
            ? '$folderTitle - $cleanFileName'
            : folderTitle;

        stories.add(
          _storyFromDriveFile(
            file,
            title: displayTitle,
            fallbackThumbnail: coverFile == null
                ? item.thumbnailLink
                : getCoverImageUrl(coverFile.id),
            metadata: info,
          ),
        );
      }
    }

    if (depth + 1 < _maxScanDepth) {
      final subFolders = children.where((file) => file.isFolder).toList();
      if (subFolders.isNotEmpty) {
        stories.addAll(await _scanFolderStories(subFolders, depth: depth + 1));
      }
    }

    return stories;
  }

  static Future<Map<String, dynamic>> _readOptionalInfoJson(
    List<_DriveFile> files,
  ) async {
    final infoFile = _findNamedFile(files, 'info.json');
    if (infoFile == null) return const {};

    try {
      final bytes = await downloadFileBytes(infoFile.id);
      final decoded = json.decode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    return const {};
  }

  static Story _storyFromDriveFile(
    _DriveFile file, {
    String? title,
    String? fallbackThumbnail,
    Map<String, dynamic> metadata = const {},
  }) {
    final coverFileId =
        _readString(metadata['coverFileId']) ??
        _readString(metadata['coverId']);
    final iconUrl =
        _readString(metadata['iconUrl']) ??
        _readString(metadata['coverUrl']) ??
        (coverFileId == null ? null : getCoverImageUrl(coverFileId)) ??
        fallbackThumbnail ??
        file.thumbnailLink;
    final totalChapters = _readInt(metadata['totalChapters']) ?? 1;

    return Story(
      id: file.id,
      title:
          title ?? _readString(metadata['title']) ?? _cleanFileName(file.name),
      titleEng: _readString(metadata['titleEng']) ?? '',
      description: _readString(metadata['description']) ?? '',
      author: _readString(metadata['author']) ?? '',
      genres: _readStringList(metadata['genres']),
      totalChapters: totalChapters < 1 ? 1 : totalChapters,
      iconUrl: iconUrl,
      driveFileId: file.id,
      isFromDrive: true,
      isLocal: false,
      fileType: file.extension,
    );
  }

  static Future<List<_DriveFile>> _listChildren(String folderId) async {
    final files = <_DriveFile>[];
    String? pageToken;

    do {
      final query = "'$folderId' in parents and trashed = false";
      final params = <String, String>{
        'q': query,
        'key': apiKey,
        'pageSize': '1000',
        'orderBy': 'folder,name',
        'fields':
            'nextPageToken,files(id,name,mimeType,thumbnailLink,modifiedTime,size)',
      };
      if (pageToken != null) {
        params['pageToken'] = pageToken;
      }

      final response = await http
          .get(Uri.https('www.googleapis.com', '/drive/v3/files', params))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Không tải được thư mục Drive: ${response.body}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      final items = data['files'] as List<dynamic>? ?? [];
      files.addAll(
        items.whereType<Map>().map(
          (item) => _DriveFile.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
      pageToken = data['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);

    return files;
  }

  static _DriveFile? _findNamedFile(List<_DriveFile> files, String name) {
    final lowerName = name.toLowerCase();
    for (final file in files) {
      if (!file.isFolder && file.name.toLowerCase() == lowerName) return file;
    }
    return null;
  }

  static _DriveFile? _findCoverFile(List<_DriveFile> files) {
    for (final file in files) {
      final lower = file.name.toLowerCase();
      if (lower.startsWith('cover.') &&
          (lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.webp'))) {
        return file;
      }
    }
    return null;
  }

  static bool _isSupportedStoryName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  static String _cleanFileName(String name) {
    return name.replaceAll(
      RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
      '',
    );
  }

  static String? _readString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static void _ensureApiKey() {
    if (apiKey.isEmpty) {
      throw Exception(
        'Thiếu GOOGLE_DRIVE_API_KEY. Hãy truyền API key bằng --dart-define.',
      );
    }
  }

  static String getThumbnailUrl(String fileId) {
    return 'https://drive.google.com/thumbnail?id=$fileId&sz=w512';
  }

  static String getCoverImageUrl(String fileId) {
    return getDownloadUrl(fileId);
  }

  static List<String> coverImageCandidates(String imagePath) {
    final trimmed = imagePath.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('http')) {
      return trimmed.isEmpty ? const [] : [trimmed];
    }

    final fileId = extractFileId(trimmed);
    if (fileId == null || fileId.isEmpty) return [trimmed];

    final isThumbnail = trimmed.contains('drive.google.com/thumbnail');
    final isMedia =
        trimmed.contains('www.googleapis.com/drive/v3/files') &&
        trimmed.contains('alt=media');
    final directUrl = apiKey.isEmpty ? '' : getCoverImageUrl(fileId);
    final thumbnailUrl = getThumbnailUrl(fileId);

    if (isMedia) {
      return _uniqueNonEmpty([trimmed, thumbnailUrl]);
    }
    if (isThumbnail) {
      return _uniqueNonEmpty([trimmed, directUrl]);
    }
    return _uniqueNonEmpty([directUrl, thumbnailUrl, trimmed]);
  }

  static String? extractFileId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http') && !trimmed.contains('/')) return trimmed;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final id = uri.queryParameters['id'];
    if (id != null && id.trim().isNotEmpty) return id.trim();

    if (uri.pathSegments.contains('d')) {
      final index = uri.pathSegments.indexOf('d');
      if (index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }

    if (uri.pathSegments.contains('files')) {
      final index = uri.pathSegments.indexOf('files');
      if (index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }

    return null;
  }

  static String getDownloadUrl(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
  }

  static List<String> _uniqueNonEmpty(List<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList();
  }

  static Future<Uint8List> downloadFileBytes(
    String fileId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    _ensureApiKey();

    final request = http.Request('GET', Uri.parse(getDownloadUrl(fileId)));
    final response = await request.send().timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final chunks = <int>[];
      var receivedBytes = 0;
      final totalBytes = response.contentLength;

      await for (final chunk in response.stream) {
        chunks.addAll(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      return Uint8List.fromList(chunks);
    }

    final errorBody = await response.stream.bytesToString();
    throw Exception('Lỗi khi tải file từ Drive: $errorBody');
  }
}

class _FolderScanResult {
  final List<Story> stories;
  final String? error;

  const _FolderScanResult({this.stories = const [], this.error});
}

class _DriveFile {
  final String id;
  final String name;
  final String mimeType;
  final String thumbnailLink;

  const _DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.thumbnailLink,
  });

  bool get isFolder => mimeType == GoogleDriveService._folderMimeType;
  bool get isStoryFile => GoogleDriveService._isSupportedStoryName(name);
  String get extension => name.split('.').last.toLowerCase();

  factory _DriveFile.fromJson(Map<String, dynamic> json) {
    return _DriveFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      thumbnailLink: json['thumbnailLink']?.toString() ?? '',
    );
  }
}
