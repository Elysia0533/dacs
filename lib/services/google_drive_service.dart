import 'dart:convert';
import 'dart:io';
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
  static const Set<String> _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
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
    final imageFiles = files.where((file) => file.isImageFile).toList();
    if (imageFiles.isEmpty) return null;

    for (final file in imageFiles) {
      final lower = file.name.toLowerCase();
      if (lower.startsWith('cover.') ||
          lower.startsWith('folder.') ||
          lower.startsWith('poster.') ||
          lower.startsWith('thumbnail.') ||
          lower.startsWith('thumb.') ||
          lower.startsWith('front.')) {
        return file;
      }
    }

    for (final file in imageFiles) {
      final lower = file.name.toLowerCase();
      if (lower.contains('cover') ||
          lower.contains('poster') ||
          lower.contains('thumbnail') ||
          lower.contains('thumb')) {
        return file;
      }
    }

    if (imageFiles.length == 1) return imageFiles.first;
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
    final directUrl = getCoverImageUrl(fileId);
    final userContentUrl = getUserContentDownloadUrl(fileId);
    final apiMediaUrl = apiKey.isEmpty ? '' : getApiDownloadUrl(fileId);
    final thumbnailUrl = getThumbnailUrl(fileId);

    if (isMedia) {
      return _uniqueNonEmpty([
        directUrl,
        userContentUrl,
        thumbnailUrl,
        trimmed,
      ]);
    }
    if (isThumbnail) {
      return _uniqueNonEmpty([trimmed, directUrl, userContentUrl, apiMediaUrl]);
    }
    return _uniqueNonEmpty([
      directUrl,
      userContentUrl,
      thumbnailUrl,
      apiMediaUrl,
      trimmed,
    ]);
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
    return 'https://drive.google.com/uc?export=download&id=$fileId';
  }

  static String getUserContentDownloadUrl(String fileId) {
    return 'https://drive.usercontent.google.com/download?id=$fileId&export=download&authuser=0';
  }

  static String getApiDownloadUrl(String fileId) {
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
    int? maxBytes,
  }) async {
    _ensureApiKey();

    final urls = _uniqueNonEmpty([
      getApiDownloadUrl(fileId),
      getDownloadUrl(fileId),
      getUserContentDownloadUrl(fileId),
    ]);
    Object? lastError;

    for (final url in urls) {
      try {
        return await _downloadBytesFromUrl(
          url,
          onProgress: onProgress,
          maxBytes: maxBytes,
        );
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Loi khi tai file tu Drive: $lastError');
  }

  static Future<File> downloadFileToFile(
    String fileId,
    File outputFile, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    _ensureApiKey();

    await outputFile.parent.create(recursive: true);
    final tempFile = File('${outputFile.path}.download');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final urls = _uniqueNonEmpty([
      getApiDownloadUrl(fileId),
      getDownloadUrl(fileId),
      getUserContentDownloadUrl(fileId),
    ]);
    Object? lastError;

    for (final url in urls) {
      try {
        await _downloadUrlToFile(url, tempFile, onProgress: onProgress);
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        return tempFile.rename(outputFile.path);
      } catch (e) {
        lastError = e;
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    }

    throw Exception('Loi khi tai file tu Drive: $lastError');
  }

  static Future<Uint8List> _downloadBytesFromUrl(
    String url, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    int? maxBytes,
    String? cookie,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    if (cookie != null && cookie.isNotEmpty) {
      request.headers['Cookie'] = cookie;
    }
    final response = await request.send().timeout(const Duration(seconds: 25));

    if (response.statusCode == 200) {
      if (_isHtmlResponse(response.headers)) {
        final htmlBytes = await response.stream.toBytes();
        final confirmUrl = _readDriveConfirmUrl(url, htmlBytes);
        if (confirmUrl != null) {
          return _downloadBytesFromUrl(
            confirmUrl,
            onProgress: onProgress,
            maxBytes: maxBytes,
            cookie: _cookieFromHeaders(response.headers),
          );
        }
        throw Exception('Drive tra ve trang HTML thay vi noi dung file.');
      }

      final chunks = <int>[];
      var receivedBytes = 0;
      final totalBytes = response.contentLength;
      if (maxBytes != null && totalBytes != null && totalBytes > maxBytes) {
        throw Exception('File qua lon de tai nen cho tac vu nay.');
      }

      await for (final chunk in response.stream) {
        chunks.addAll(chunk);
        receivedBytes += chunk.length;
        if (maxBytes != null && receivedBytes > maxBytes) {
          throw Exception('File qua lon de tai nen cho tac vu nay.');
        }
        onProgress?.call(receivedBytes, totalBytes);
      }

      final bytes = Uint8List.fromList(chunks);
      if (_looksLikeHtml(bytes)) {
        throw Exception('Drive tra ve trang HTML thay vi noi dung file.');
      }
      return bytes;
    }

    final errorBody = await response.stream.bytesToString();
    throw Exception('Lỗi khi tải file từ Drive: $errorBody');
  }

  static Future<void> _downloadUrlToFile(
    String url,
    File outputFile, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    String? cookie,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    if (cookie != null && cookie.isNotEmpty) {
      request.headers['Cookie'] = cookie;
    }
    final response = await request.send().timeout(const Duration(seconds: 25));

    if (response.statusCode == 200) {
      if (_isHtmlResponse(response.headers)) {
        final htmlBytes = await response.stream.toBytes();
        final confirmUrl = _readDriveConfirmUrl(url, htmlBytes);
        if (confirmUrl != null) {
          return _downloadUrlToFile(
            confirmUrl,
            outputFile,
            onProgress: onProgress,
            cookie: _cookieFromHeaders(response.headers),
          );
        }
        throw Exception('Drive tra ve trang HTML thay vi noi dung file.');
      }

      final sink = outputFile.openWrite();
      var receivedBytes = 0;
      final totalBytes = response.contentLength;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(receivedBytes, totalBytes);
        }
      } finally {
        await sink.close();
      }
      return;
    }

    final errorBody = await response.stream.bytesToString();
    throw Exception('Lỗi khi tải file từ Drive: $errorBody');
  }

  static bool _isHtmlResponse(Map<String, String> headers) {
    return (headers['content-type'] ?? '').toLowerCase().contains('text/html');
  }

  static String? _cookieFromHeaders(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null || raw.isEmpty) return null;
    return raw
        .split(',')
        .map((part) => part.split(';').first.trim())
        .where((part) => part.contains('='))
        .join('; ');
  }

  static String? _readDriveConfirmUrl(String baseUrl, Uint8List htmlBytes) {
    final html = utf8
        .decode(htmlBytes, allowMalformed: true)
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    final linkPatterns = [
      RegExp(
        r'''href=["']([^"']*(?:uc\?export=download|drive\.usercontent\.google\.com/download)[^"']*confirm=[^"']*)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'"downloadUrl"\s*:\s*"([^"]+confirm=[^"]+)"',
        caseSensitive: false,
      ),
    ];

    for (final pattern in linkPatterns) {
      final match = pattern.firstMatch(html);
      final rawUrl = match?.group(1);
      if (rawUrl != null && rawUrl.isNotEmpty) {
        return _resolveDriveUrl(baseUrl, rawUrl.replaceAll(r'\/', '/'));
      }
    }

    final actionMatch = RegExp(
      r'''<form[^>]+action=["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (actionMatch == null) return null;

    final params = <String, String>{};
    final inputPattern = RegExp(
      r'''<input[^>]+name=["']([^"']+)["'][^>]+value=["']([^"']*)["']''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in inputPattern.allMatches(html)) {
      final name = match.group(1);
      final value = match.group(2);
      if (name != null && value != null) params[name] = value;
    }

    if (!params.containsKey('confirm')) return null;
    final actionUrl = _resolveDriveUrl(baseUrl, actionMatch.group(1)!);
    final uri = Uri.parse(actionUrl);
    return uri
        .replace(queryParameters: {...uri.queryParameters, ...params})
        .toString();
  }

  static String _resolveDriveUrl(String baseUrl, String rawUrl) {
    if (rawUrl.startsWith('//')) return 'https:$rawUrl';
    return Uri.parse(baseUrl).resolve(rawUrl).toString();
  }

  static bool _looksLikeHtml(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final sampleLength = bytes.length < 512 ? bytes.length : 512;
    final sample = utf8
        .decode(bytes.sublist(0, sampleLength), allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    return sample.startsWith('<!doctype html') || sample.startsWith('<html');
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
  bool get isImageFile =>
      GoogleDriveService._imageExtensions.contains(extension);

  factory _DriveFile.fromJson(Map<String, dynamic> json) {
    return _DriveFile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      thumbnailLink: json['thumbnailLink']?.toString() ?? '',
    );
  }
}
