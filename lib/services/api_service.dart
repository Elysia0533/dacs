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
import '../models/app_user.dart';
import '../models/community_message.dart';
import '../models/story.dart';
import 'firebase_backend_service.dart';
import 'google_drive_service.dart';

class RegisterResult {
  final AppUser user;
  final bool emailVerificationRequired;

  const RegisterResult({
    required this.user,
    required this.emailVerificationRequired,
  });
}

class EmailVerificationResult {
  final bool ok;
  final bool alreadyVerified;

  const EmailVerificationResult({
    required this.ok,
    this.alreadyVerified = false,
  });
}

class ApiService {
  static const String _localStoriesKey = 'local_imported_stories';
  static const String _serverStoriesKey = 'drive_story_catalog_cache';
  static const String _serverStoriesCachedAtKey =
      'drive_story_catalog_cache_at';
  static const Duration _driveCatalogCacheTtl = Duration(minutes: 30);
  static const String _authTokenKey = 'firebase_auth_token';
  static const String _authUserKey = 'firebase_auth_user';
  static const String _localAccountsKey = 'local_accounts';
  static const String _localCommunityMessagesKey = 'local_community_messages';
  static final Map<String, Timer> _scrollSaveTimers = {};

  static Future<Map<String, dynamic>> extractEpubMetadata(
    String filePath,
  ) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      final book = await epubx.EpubReader.readBook(bytes);
      final meta = book.Schema?.Package?.Metadata;

      String title = book.Title ?? '';
      String author = book.Author ?? '';
      List<String> genres = [];
      String description = '';
      final chapterCount = _countReadableChapters(book.Chapters ?? []);

      if (meta != null) {
        if (meta.Subjects != null && meta.Subjects!.isNotEmpty) {
          genres = List<String>.from(meta.Subjects!);
        }
        if (meta.Description != null && meta.Description!.isNotEmpty) {
          description = meta.Description!;
        }
        if (author.isEmpty &&
            meta.Creators != null &&
            meta.Creators!.isNotEmpty) {
          author = meta.Creators!.first.Creator ?? '';
        }
      }

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

  static Future<List<Story>> fetchServerStories() async {
    return _fetchDriveStoriesAndCache(useFreshCache: true);
  }

  static Future<List<Story>> _fetchDriveStoriesAndCache({
    String? folderUrl,
    bool useFreshCache = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedStoriesJson = prefs.getStringList(_serverStoriesKey) ?? [];

    if (folderUrl == null && useFreshCache && cachedStoriesJson.isNotEmpty) {
      final cachedAtMillis = prefs.getInt(_serverStoriesCachedAtKey) ?? 0;
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMillis);
      final isFresh =
          DateTime.now().difference(cachedAt) < _driveCatalogCacheTtl;
      if (isFresh) {
        return _decodeStoryCache(cachedStoriesJson);
      }
    }

    try {
      final items = folderUrl == null
          ? await GoogleDriveService.fetchStoriesFromConfiguredFolder()
          : await GoogleDriveService.fetchStoriesFromFolders(
              GoogleDriveService.parseFolderInputs(folderUrl),
            );
      final updatedJson = items.map((s) => json.encode(s.toJson())).toList();
      await prefs.setStringList(_serverStoriesKey, updatedJson);
      await prefs.setInt(
        _serverStoriesCachedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      return items;
    } catch (e) {
      debugPrint('Không thể tải danh sách truyện từ Drive: $e');
      if (cachedStoriesJson.isNotEmpty) {
        return _decodeStoryCache(cachedStoriesJson);
      }
      rethrow;
    }
  }

  static List<Story> _decodeStoryCache(List<String> storiesJson) {
    return storiesJson.map((s) => Story.fromJson(json.decode(s))).toList();
  }

  static Future<List<Story>> refreshServerStories() async {
    return _fetchDriveStoriesAndCache();
  }

  static Future<List<Story>> fetchDriveStoriesFromFolder(String folderUrl) {
    return _fetchDriveStoriesAndCache(folderUrl: folderUrl);
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

  static Future<void> mergeCloudLibraryIntoLocal() async {
    try {
      final cloudStories =
          await FirebaseBackendService.fetchCloudLibraryStories();
      if (cloudStories.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];
      final localStories = localStoriesJson
          .map((s) => Story.fromJson(json.decode(s)))
          .toList();

      for (final cloudStory in cloudStories.reversed) {
        final exists = localStories.any((story) {
          final sameId = story.id == cloudStory.id;
          final sameDriveFile =
              cloudStory.driveFileId.isNotEmpty &&
              story.driveFileId == cloudStory.driveFileId;
          return sameId || sameDriveFile;
        });
        if (!exists) {
          localStories.insert(0, cloudStory);
        }
      }

      await prefs.setStringList(
        _localStoriesKey,
        localStories.map((story) => json.encode(story.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('Không thể tải thư viện đồng bộ về máy: $e');
    }
  }

  static Future<RegisterResult> registerWithBackend({
    required String email,
    required String password,
    required String displayName,
  }) async {
    if (!FirebaseBackendService.isInitialized) {
      final user = await _registerLocalAccount(
        email: email,
        password: password,
        displayName: displayName,
      );
      return RegisterResult(user: user, emailVerificationRequired: false);
    }

    final user = await FirebaseBackendService.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    return RegisterResult(
      user: user,
      emailVerificationRequired: !user.emailVerified,
    );
  }

  static Future<AppUser> verifyEmailWithBackend({
    required String email,
    required String code,
  }) async {
    if (!FirebaseBackendService.isInitialized) {
      final user = await getSavedUser();
      if (user == null || user.email.toLowerCase() != email.toLowerCase()) {
        throw Exception('Hãy đăng nhập lại bằng email vừa đăng ký.');
      }
      return user;
    }

    final user = await FirebaseBackendService.confirmEmailVerified(
      email: email,
    );
    await _saveAuthSession(user, user.id);
    return user;
  }

  static Future<EmailVerificationResult> resendVerificationCode({
    required String email,
  }) async {
    if (!FirebaseBackendService.isInitialized) {
      return const EmailVerificationResult(ok: true, alreadyVerified: true);
    }

    await FirebaseBackendService.resendVerificationEmail(email: email);
    return const EmailVerificationResult(ok: true);
  }

  static Future<AppUser> loginWithBackend({
    required String email,
    required String password,
  }) async {
    if (!FirebaseBackendService.isInitialized) {
      return _loginLocalAccount(email: email, password: password);
    }

    final user = await FirebaseBackendService.login(
      email: email,
      password: password,
    );
    await _saveAuthSession(user, user.id);
    return user;
  }

  static Future<AppUser?> refreshCurrentUser() async {
    if (!FirebaseBackendService.isInitialized) {
      return getSavedUser();
    }

    try {
      final user = await FirebaseBackendService.refreshCurrentUser();
      if (user == null) return null;
      await _saveAuthSession(user, user.id);
      return user;
    } catch (e) {
      debugPrint('Không thể làm mới phiên đăng nhập: $e');
      return getSavedUser();
    }
  }

  static Future<void> logoutBackend() async {
    await FirebaseBackendService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_authUserKey);
  }

  static Future<List<CommunityMessage>> fetchCommunityMessages() async {
    if (!FirebaseBackendService.isInitialized) {
      return _fetchLocalCommunityMessages();
    }

    return FirebaseBackendService.fetchCommunityMessages();
  }

  static Future<CommunityMessage> sendCommunityMessage(String text) async {
    if (!FirebaseBackendService.isInitialized) {
      return _sendLocalCommunityMessage(text);
    }

    return FirebaseBackendService.sendCommunityMessage(text);
  }

  static Future<AppUser> _registerLocalAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw Exception('Email không hợp lệ.');
    }
    if (password.length < 6) {
      throw Exception('Mật khẩu cần ít nhất 6 ký tự.');
    }
    if (displayName.trim().isEmpty) {
      throw Exception('Vui lòng nhập tên hiển thị.');
    }

    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList(_localAccountsKey) ?? [];
    final decodedAccounts = accounts
        .map((raw) => json.decode(raw) as Map<String, dynamic>)
        .toList();

    final exists = decodedAccounts.any(
      (account) =>
          account['email']?.toString().toLowerCase() == normalizedEmail,
    );
    if (exists) {
      throw Exception('Email này đã được đăng ký.');
    }

    final user = AppUser(
      id: 'local_${const Uuid().v4()}',
      email: normalizedEmail,
      displayName: displayName.trim(),
      role: 'user',
      emailVerified: true,
    );

    decodedAccounts.add({...user.toJson(), 'password': password});
    await prefs.setStringList(
      _localAccountsKey,
      decodedAccounts.map((account) => json.encode(account)).toList(),
    );
    await _saveAuthSession(user, user.id);
    return user;
  }

  static Future<AppUser> _loginLocalAccount({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList(_localAccountsKey) ?? [];

    Map<String, dynamic>? found;
    for (final rawAccount in accounts) {
      final account = json.decode(rawAccount) as Map<String, dynamic>;
      if (account['email']?.toString().toLowerCase() == normalizedEmail) {
        found = account;
        break;
      }
    }

    if (found == null) {
      throw Exception('Không tìm thấy tài khoản với email này.');
    }
    if (found['password']?.toString() != password) {
      throw Exception('Mật khẩu không đúng.');
    }

    final user = AppUser.fromJson(found);
    await _saveAuthSession(user, user.id);
    return user;
  }

  static Future<List<CommunityMessage>> _fetchLocalCommunityMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMessages = prefs.getStringList(_localCommunityMessagesKey) ?? [];
    final messages = rawMessages
        .map(
          (raw) => CommunityMessage.fromJson(
            Map<String, dynamic>.from(json.decode(raw) as Map),
          ),
        )
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  static Future<CommunityMessage> _sendLocalCommunityMessage(
    String text,
  ) async {
    final user = await getSavedUser();
    final token = await getSavedAuthToken();
    if (user == null || token == null || token.isEmpty) {
      throw Exception('Cần đăng nhập để gửi tin nhắn.');
    }

    final message = CommunityMessage(
      id: 'local_${const Uuid().v4()}',
      userId: user.id,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
    );

    final prefs = await SharedPreferences.getInstance();
    final messages = await _fetchLocalCommunityMessages();
    messages.add(message);
    final recentMessages = messages.length > 100
        ? messages.sublist(messages.length - 100)
        : messages;
    await prefs.setStringList(
      _localCommunityMessagesKey,
      recentMessages.map((item) => json.encode(item.toJson())).toList(),
    );
    return message;
  }

  static Future<void> _syncStoryToBackendLibrary(Story story) async {
    try {
      await FirebaseBackendService.syncStoryToLibrary(story);
    } catch (e) {
      debugPrint('Không thể đồng bộ thư viện: $e');
    }
  }

  static Future<void> _syncProgressToBackend(
    String storyId,
    int chapterIndex, {
    int? totalChapters,
    double? scrollOffset,
  }) async {
    try {
      await FirebaseBackendService.syncProgress(
        storyId,
        chapterIndex,
        totalChapters: totalChapters,
        scrollOffset: scrollOffset,
      );
    } catch (e) {
      debugPrint('Không thể đồng bộ tiến độ đọc: $e');
    }
  }

  static Future<void> _removeStoryFromBackendLibrary(String storyId) async {
    try {
      await FirebaseBackendService.removeStoryFromLibrary(storyId);
    } catch (e) {
      debugPrint('Cannot remove story from synced library: $e');
    }
  }

  static Future<void> importLocalStory(Story story) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];

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
    await prefs.remove('scroll_$storyId');
    await _removeStoryFromBackendLibrary(storyId);
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

  static Future<void> saveScrollOffset(String storyId, double offset) async {
    _scrollSaveTimers[storyId]?.cancel();
    _scrollSaveTimers[storyId] = Timer(
      const Duration(milliseconds: 600),
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('scroll_$storyId', offset);

          final story = await _findLocalStory(storyId);
          await _syncProgressToBackend(
            storyId,
            story?.savedChapterIndex ?? 0,
            totalChapters: story?.totalChapters ?? 1,
            scrollOffset: offset,
          );
        } catch (e) {
          debugPrint('Cannot save scroll offset: $e');
        }
      },
    );
  }

  static Future<Story?> _findLocalStory(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    final localStoriesJson = prefs.getStringList(_localStoriesKey) ?? [];

    for (final rawStory in localStoriesJson) {
      final story = Story.fromJson(json.decode(rawStory));
      if (story.id == storyId) return story;
    }

    return null;
  }

  static Future<double> getScrollOffset(String storyId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('scroll_$storyId') ?? 0.0;
  }

  static Future<Story?> getLastReadStory() async {
    final stories = await fetchPersonalStories();
    if (stories.isEmpty) return null;
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

        final displayTitle = fileName.replaceAll(
          RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
          '',
        );

        bool exists = localStoriesJson.any((s) {
          final decoded = json.decode(s);
          final sameTitle =
              decoded['title'] == displayTitle && decoded['isLocal'] == true;
          final sameLocalPath = decoded['localPath'] == localFile.path;
          return sameTitle || sameLocalPath;
        });

        if (!exists) {
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
            fileType: fileName.split('.').last.toLowerCase(),
          );

          if (fileName.endsWith('.txt')) {
            newStory = Story(
              id: newStory.id,
              title: displayTitle,
              content: await localFile.readAsString(),
              localPath: localFile.path,
              isLocal: true,
              fileType: fileName.split('.').last.toLowerCase(),
            );
          }

          localStoriesJson.insert(0, json.encode(newStory.toJson()));
        }
      }

      await prefs.setStringList(_localStoriesKey, localStoriesJson);
    } catch (e) {
      debugPrint('Lỗi khởi tạo offline stories: $e');
    }
  }
}
