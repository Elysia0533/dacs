import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:epub_view/epub_view.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import '../models/app_user.dart';
import '../models/community_message.dart';
import '../models/story.dart';

class ApiService {
  static const String _localStoriesKey = 'local_imported_stories';
  static const String _serverStoriesKey = 'server_stories';
  static const String _authTokenKey = 'backend_auth_token';
  static const String _authUserKey = 'backend_auth_user';
  static const String _apiBaseUrl = String.fromEnvironment(
    'VBOOK_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );

  static String get apiBaseUrl => _apiBaseUrl;

  static Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    final base = Uri.parse(_apiBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final endpoint = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '$basePath$endpoint',
      queryParameters: queryParameters,
    );
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool authenticated = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };

    if (authenticated) {
      final token = await getSavedAuthToken();
      if (token == null || token.isEmpty) {
        throw Exception('Cần đăng nhập để gọi API này');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = _apiUri(path, queryParameters);
    final encodedBody = body == null ? null : json.encode(body);

    late final http.Response response;
    try {
      response = switch (method) {
        'GET' =>
          await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12)),
        'POST' =>
          await http
              .post(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 12)),
        'PUT' =>
          await http
              .put(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 12)),
        'PATCH' =>
          await http
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 12)),
        'DELETE' =>
          await http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 12)),
        _ => throw Exception('HTTP method không hỗ trợ: $method'),
      };
    } on TimeoutException catch (e) {
      throw Exception('Không kết nối được backend tại $_apiBaseUrl: $e');
    } on http.ClientException catch (e) {
      throw Exception('Không kết nối được backend tại $_apiBaseUrl: $e');
    }

    final dynamic responseBody;
    try {
      responseBody = response.body.isEmpty
          ? <String, dynamic>{}
          : json.decode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw Exception('Phản hồi backend không phải JSON hợp lệ: $e');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return responseBody;
    }

    if (responseBody is Map && responseBody['error'] != null) {
      throw Exception(responseBody['error']);
    }
    throw Exception('Backend trả về HTTP ${response.statusCode}');
  }

  static Story _storyFromBackendJson(Map<String, dynamic> json) {
    final driveFileId = json['driveFileId']?.toString() ?? '';
    return Story(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      titleEng: json['titleEng']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      genres:
          (json['genres'] as List<dynamic>?)
              ?.map((genre) => genre.toString())
              .toList() ??
          [],
      totalChapters: json['totalChapters'] is int
          ? json['totalChapters'] as int
          : int.tryParse(json['totalChapters']?.toString() ?? '') ?? 1,
      iconUrl: json['iconUrl']?.toString() ?? '',
      driveFileId: driveFileId,
      isFromDrive: driveFileId.isNotEmpty,
      isLocal: false,
    );
  }

  static Map<String, dynamic> _storyToBackendPayload(Story story) {
    final fileType = story.localPath.isNotEmpty
        ? story.localPath.split('.').last.toLowerCase()
        : '';
    return {
      'title': story.title,
      'titleEng': story.titleEng,
      'author': story.author,
      'description': story.description,
      'genres': story.genres,
      'totalChapters': story.totalChapters,
      'iconUrl': story.iconUrl.startsWith('http') ? story.iconUrl : '',
      'driveFileId': story.driveFileId,
      'fileType': fileType,
      'isPublished': true,
    };
  }

  // Trích xuất metadata EPUB: title, author, genres (subjects), description, coverPath
  static Future<Map<String, dynamic>> extractEpubMetadata(
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      // Dùng epubx để lấy đầy đủ schema metadata
      final book = await epubx.EpubReader.readBook(bytes);
      final meta = book.Schema?.Package?.Metadata;

      String title = book.Title ?? '';
      String author = book.Author ?? '';
      List<String> genres = [];
      String description = '';
      final chapterCount = _countReadableChapters(book.Chapters ?? []);

      if (meta != null) {
        // Subjects = thể loại
        if (meta.Subjects != null && meta.Subjects!.isNotEmpty) {
          genres = List<String>.from(meta.Subjects!);
        }
        // Description
        if (meta.Description != null && meta.Description!.isNotEmpty) {
          description = meta.Description!;
        }
        // Author (dự phòng nếu book.Author trống)
        if (author.isEmpty &&
            meta.Creators != null &&
            meta.Creators!.isNotEmpty) {
          author = meta.Creators!.first.Creator ?? '';
        }
      }

      // Lấy ảnh bìa từ epub_view (vì epubx không decode hình)
      String coverPath = '';
      try {
        final document = await EpubDocument.openData(bytes);
        if (document.CoverImage != null) {
          final directory = await getApplicationDocumentsDirectory();
          final coverFileName = 'cover_${const Uuid().v4()}.jpg';
          final coverFile = File('${directory.path}/$coverFileName');
          final jpgBytes = img.encodeJpg(document.CoverImage!);
          await coverFile.writeAsBytes(jpgBytes);
          coverPath = coverFile.path;
        }
      } catch (_) {}

      return {
        'title': title,
        'author': author,
        'genres': genres,
        'chapterCount': chapterCount > 0 ? chapterCount : 1,
        'coverPath': coverPath,
        'description': description,
      };
    } catch (e) {
      debugPrint('Lỗi đọc epub metadata: $e');
      return {};
    }
  }

  // Lấy danh sách truyện trong Thư viện cá nhân
  static int _countReadableChapters(List<epubx.EpubChapter> chapters) {
    var count = 0;
    for (final chapter in chapters) {
      if ((chapter.HtmlContent ?? '').trim().isNotEmpty) {
        count++;
      }
      final subChapters = chapter.SubChapters;
      if (subChapters != null && subChapters.isNotEmpty) {
        count += _countReadableChapters(subChapters);
      }
    }
    return count;
  }

  static Future<List<Story>> fetchPersonalStories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];
    return localStoriesJson.map((s) => Story.fromJson(json.decode(s))).toList();
  }

  // Lấy danh sách truyện từ backend thật, có cache local dự phòng.
  static Future<List<Story>> fetchServerStories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> serverStoriesJson =
        prefs.getStringList(_serverStoriesKey) ?? [];

    try {
      return await _fetchBackendStoriesAndCache();
    } catch (e) {
      debugPrint('Lỗi tải truyện từ backend: $e');
      if (serverStoriesJson.isNotEmpty) {
        return serverStoriesJson
            .map((s) => Story.fromJson(json.decode(s)))
            .toList();
      }
      rethrow;
    }
  }

  static Future<List<Story>> _fetchBackendStoriesAndCache() async {
    final data = await _request(
      'GET',
      '/stories',
      queryParameters: {'limit': '100'},
    );
    final items = (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => _storyFromBackendJson(Map<String, dynamic>.from(item)))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final updatedJson = items.map((s) => json.encode(s.toJson())).toList();
    await prefs.setStringList(_serverStoriesKey, updatedJson);
    return items;
  }

  // Admin: tải lại danh sách truyện từ backend thật.
  static Future<List<Story>> refreshServerStories() async {
    return _fetchBackendStoriesAndCache();
  }

  // Admin thêm truyện mới vào backend.
  static Future<void> addServerStories(List<Story> newStories) async {
    for (final story in newStories) {
      await _request(
        'POST',
        '/stories',
        body: _storyToBackendPayload(story),
        authenticated: true,
      );
    }
    await _fetchBackendStoriesAndCache();
  }

  static Future<String?> getSavedAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  static Future<AppUser?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rawUser = prefs.getString(_authUserKey);
    if (rawUser == null || rawUser.isEmpty) return null;
    return AppUser.fromJson(json.decode(rawUser) as Map<String, dynamic>);
  }

  static Future<void> _saveAuthSession(AppUser user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authTokenKey, token);
    await prefs.setString(_authUserKey, json.encode(user.toJson()));
  }

  static Future<AppUser> registerWithBackend({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = await _request(
      'POST',
      '/auth/register',
      body: {'email': email, 'password': password, 'displayName': displayName},
    );
    final user = AppUser.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await _saveAuthSession(user, data['token']?.toString() ?? '');
    return user;
  }

  static Future<AppUser> loginWithBackend({
    required String email,
    required String password,
  }) async {
    final data = await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    final user = AppUser.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await _saveAuthSession(user, data['token']?.toString() ?? '');
    return user;
  }

  static Future<AppUser?> refreshCurrentUser() async {
    final token = await getSavedAuthToken();
    if (token == null || token.isEmpty) return null;
    try {
      final data = await _request('GET', '/auth/me', authenticated: true);
      final user = AppUser.fromJson(
        Map<String, dynamic>.from(data['user'] as Map),
      );
      await _saveAuthSession(user, token);
      return user;
    } catch (e) {
      debugPrint('Không thể làm mới phiên đăng nhập: $e');
      return getSavedUser();
    }
  }

  static Future<void> logoutBackend() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_authUserKey);
  }

  static Future<List<CommunityMessage>> fetchCommunityMessages() async {
    final data = await _request(
      'GET',
      '/community/messages',
      queryParameters: {'limit': '50'},
    );
    return (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (item) => CommunityMessage.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static Future<CommunityMessage> sendCommunityMessage(String text) async {
    final data = await _request(
      'POST',
      '/community/messages',
      body: {'text': text},
      authenticated: true,
    );
    return CommunityMessage.fromJson(
      Map<String, dynamic>.from(data['message'] as Map),
    );
  }

  static Future<void> _syncStoryToBackendLibrary(Story story) async {
    final token = await getSavedAuthToken();
    if (token == null || token.isEmpty) return;

    try {
      await _request(
        'POST',
        '/me/library',
        body: {
          'storyId': story.id,
          'localPath': story.localPath,
          'savedChapterIndex': story.savedChapterIndex,
          'totalChapters': story.totalChapters,
        },
        authenticated: true,
      );
    } catch (e) {
      debugPrint('Không thể đồng bộ thư viện lên backend: $e');
    }
  }

  static Future<void> _syncProgressToBackend(
    String storyId,
    int chapterIndex, {
    int? totalChapters,
  }) async {
    final token = await getSavedAuthToken();
    if (token == null || token.isEmpty) return;

    try {
      await _request(
        'PUT',
        '/me/library/$storyId/progress',
        body: {
          'savedChapterIndex': chapterIndex,
          'totalChapters': totalChapters ?? 1,
        },
        authenticated: true,
      );
    } catch (e) {
      debugPrint('Không thể đồng bộ tiến độ đọc lên backend: $e');
    }
  }

  static Future<void> importLocalStory(Story story) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];

    // Kiểm tra xem đã tồn tại chưa (dựa theo id)
    bool exists = localStoriesJson.any((s) {
      final decoded = json.decode(s);
      final sameId = decoded['id'] == story.id;
      final sameDriveFile =
          story.driveFileId.isNotEmpty &&
          decoded['driveFileId'] == story.driveFileId;
      final sameLocalPath =
          story.localPath.isNotEmpty && decoded['localPath'] == story.localPath;
      return sameId || sameDriveFile || sameLocalPath;
    });

    if (!exists) {
      localStoriesJson.insert(0, json.encode(story.toJson()));
      await prefs.setStringList(_localStoriesKey, localStoriesJson);
    }
    await _syncStoryToBackendLibrary(story);
  }

  static Future<Story?> updateLocalStory(Story updatedStory) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];
    List<Story> localStories = localStoriesJson
        .map((s) => Story.fromJson(json.decode(s)))
        .toList();

    int index = localStories.indexWhere((s) {
      final sameId = s.id == updatedStory.id;
      final sameDriveFile =
          updatedStory.driveFileId.isNotEmpty &&
          s.driveFileId == updatedStory.driveFileId;
      final sameLocalPath =
          updatedStory.localPath.isNotEmpty &&
          s.localPath == updatedStory.localPath;
      return sameId || sameDriveFile || sameLocalPath;
    });
    if (index != -1) {
      final existingStory = localStories[index];
      final savedStory = updatedStory.copyWith(
        id: existingStory.id,
        currentChapter: existingStory.currentChapter,
        savedChapterIndex: existingStory.savedChapterIndex > 0
            ? existingStory.savedChapterIndex
            : updatedStory.savedChapterIndex,
      );
      localStories[index] = savedStory;
      List<String> updatedJson = localStories
          .map((s) => json.encode(s.toJson()))
          .toList();
      await prefs.setStringList(_localStoriesKey, updatedJson);
      await _syncStoryToBackendLibrary(savedStory);
      return savedStory;
    }
    return null;
  }

  // Xóa truyện khỏi thư viện cá nhân
  static Future<void> deleteLocalStory(String storyId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];
    final removedStories = <Map<String, dynamic>>[];
    localStoriesJson.removeWhere((s) {
      final decoded = json.decode(s) as Map<String, dynamic>;
      final shouldRemove = decoded['id'] == storyId;
      if (shouldRemove) {
        removedStories.add(decoded);
      }
      return shouldRemove;
    });
    await prefs.setStringList(_localStoriesKey, localStoriesJson);
    await _deleteOwnedStoryFiles(removedStories);
    // Xóa luôn vị trí cuộn đã lưu
    await prefs.remove('scroll_$storyId');
  }

  static Future<void> _deleteOwnedStoryFiles(
    List<Map<String, dynamic>> stories,
  ) async {
    if (stories.isEmpty) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final appDirPath = Directory(directory.path).absolute.path;

      for (final story in stories) {
        await _deleteIfOwned(story['localPath'], appDirPath);
        final iconUrl = story['iconUrl'];
        if (iconUrl is String && !iconUrl.startsWith('http')) {
          await _deleteIfOwned(iconUrl, appDirPath);
        }
      }
    } catch (e) {
      debugPrint('Lỗi xóa file truyện: $e');
    }
  }

  static Future<void> _deleteIfOwned(dynamic rawPath, String appDirPath) async {
    if (rawPath is! String || rawPath.isEmpty) return;

    final file = File(rawPath);
    final filePath = file.absolute.path;
    if (!filePath.startsWith(appDirPath)) return;
    if (await file.exists()) {
      await file.delete();
    }
  }

  // Lưu vị trí cuộn (dùng cho TXT reader)
  static Future<void> saveScrollOffset(String storyId, double offset) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('scroll_$storyId', offset);
  }

  // Lấy vị trí cuộn đã lưu
  static Future<double> getScrollOffset(String storyId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('scroll_$storyId') ?? 0.0;
  }

  // Lấy truyện đọc gần nhất (có savedChapterIndex > 0 hoặc có scroll offset)
  static Future<Story?> getLastReadStory() async {
    final stories = await fetchPersonalStories();
    if (stories.isEmpty) return null;
    // Ưu tiên truyện có tiến trình (savedChapterIndex > 0)
    final withProgress = stories.where((s) => s.savedChapterIndex > 0).toList();
    if (withProgress.isNotEmpty) return withProgress.first;
    return stories.first;
  }

  static Future<void> saveChapterProgress(
    String storyId,
    int chapterIndex, {
    int? totalChapters,
  }) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Lưu trong local
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];
    List<Story> localStories = localStoriesJson
        .map((s) => Story.fromJson(json.decode(s)))
        .toList();
    int localIndex = localStories.indexWhere((s) => s.id == storyId);
    if (localIndex != -1) {
      localStories[localIndex] = localStories[localIndex].copyWith(
        savedChapterIndex: chapterIndex,
        totalChapters: totalChapters,
      );
      List<String> updatedJson = localStories
          .map((s) => json.encode(s.toJson()))
          .toList();
      await prefs.setStringList(_localStoriesKey, updatedJson);
    }

    // Lưu trong server (cho mục Khám phá)
    List<String> serverStoriesJson =
        prefs.getStringList(_serverStoriesKey) ?? [];
    List<Story> serverStories = serverStoriesJson
        .map((s) => Story.fromJson(json.decode(s)))
        .toList();
    int serverIndex = serverStories.indexWhere((s) => s.id == storyId);
    if (serverIndex != -1) {
      serverStories[serverIndex] = serverStories[serverIndex].copyWith(
        savedChapterIndex: chapterIndex,
        totalChapters: totalChapters,
      );
      List<String> updatedServerJson = serverStories
          .map((s) => json.encode(s.toJson()))
          .toList();
      await prefs.setStringList(_serverStoriesKey, updatedServerJson);
    }

    await _syncProgressToBackend(
      storyId,
      chapterIndex,
      totalChapters: totalChapters,
    );
  }

  // Khởi tạo các file truyện từ assets/offline_stories/
  static Future<void> initOfflineStories() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

      final offlineAssetPaths = manifest
          .listAssets()
          .where((String key) => key.startsWith('assets/offline_stories/'))
          .toList();

      if (offlineAssetPaths.isEmpty) return;

      final directory = await getApplicationDocumentsDirectory();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> localStoriesJson =
          prefs.getStringList(_localStoriesKey) ?? [];

      for (String assetPath in offlineAssetPaths) {
        final fileName = assetPath.split('/').last;
        final localFile = File('${directory.path}/$fileName');

        // Tạo title đẹp hơn bằng cách bỏ đuôi file (ví dụ: ThanhXuan_Vol1.epub -> ThanhXuan_Vol1)
        final displayTitle = fileName.replaceAll(
          RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
          '',
        );

        // Kiểm tra xem truyện này đã được thêm vào trước đó chưa (tránh copy lại)
        bool exists = localStoriesJson.any((s) {
          final decoded = json.decode(s);
          final sameTitle =
              decoded['title'] == displayTitle && decoded['isLocal'] == true;
          final sameLocalPath = decoded['localPath'] == localFile.path;
          return sameTitle || sameLocalPath;
        });

        if (!exists) {
          // Copy từ asset ra bộ nhớ trong
          final byteData = await rootBundle.load(assetPath);
          await localFile.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          );

          String extractedTitle = displayTitle;
          String coverPath = '';
          String description = '';
          String author = '';
          List<String> genres = [];
          int totalChapters = 1;
          if (fileName.toLowerCase().endsWith('.epub')) {
            final metadata = await extractEpubMetadata(localFile.path);
            if (metadata['title'] != null && metadata['title']!.isNotEmpty) {
              extractedTitle = metadata['title']!;
            }
            if (metadata['coverPath'] != null) {
              coverPath = metadata['coverPath']!;
            }
            if (metadata['description'] != null) {
              description = metadata['description']!;
            }
            final metadataAuthor = metadata['author'];
            if (metadataAuthor is String) {
              author = metadataAuthor;
            }
            final metadataGenres = metadata['genres'];
            if (metadataGenres is List) {
              genres = metadataGenres.map((genre) => genre.toString()).toList();
            }
            final metadataChapterCount = metadata['chapterCount'];
            if (metadataChapterCount is int && metadataChapterCount > 0) {
              totalChapters = metadataChapterCount;
            }
          }

          Story newStory = Story(
            id: const Uuid().v4(),
            title: extractedTitle,
            description: description,
            author: author,
            genres: genres,
            totalChapters: totalChapters,
            localPath: localFile.path,
            isLocal: true,
            iconUrl: coverPath,
          );

          if (fileName.endsWith('.txt')) {
            newStory = Story(
              id: newStory.id,
              title: displayTitle,
              content: await localFile.readAsString(),
              localPath: localFile.path,
              isLocal: true,
            );
          }

          // Trực tiếp thêm vào list hiện tại để vòng lặp sau nhận biết
          localStoriesJson.insert(0, json.encode(newStory.toJson()));
        }
      }

      // Lưu lại toàn bộ danh sách cập nhật
      await prefs.setStringList(_localStoriesKey, localStoriesJson);
    } catch (e) {
      debugPrint('Lỗi khởi tạo offline stories: $e');
    }
  }
}
