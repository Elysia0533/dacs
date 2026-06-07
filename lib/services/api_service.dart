import 'dart:convert';
import 'dart:async';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:epub_view/epub_view.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';
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
  static const int _maxDriveCoverDownloadBytes = 60 * 1024 * 1024;
  static const String _authTokenKey = 'firebase_auth_token';
  static const String _authUserKey = 'firebase_auth_user';
  static const String _localAccountsKey = 'local_accounts';
  static const String _localCommunityMessagesKey = 'local_community_messages';
  static final Map<String, Timer> _scrollSaveTimers = {};
  static final Map<String, Future<String?>> _driveCoverTasks = {};
  static final Set<String> _driveCoverMisses = {};
  static final Set<String> _localCoverRepairMisses = {};

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
        final directory = await getApplicationDocumentsDirectory();
        final coverFileName = 'cover_${const Uuid().v4()}.jpg';
        final coverFile = File('${directory.path}/$coverFileName');
        coverPath = await _writeEpubCover(bytes, coverFile);
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

  static Future<String?> getCachedDriveCoverPath({
    required String driveFileId,
    required String fileType,
  }) async {
    final normalizedType = fileType.trim().toLowerCase();
    final id = driveFileId.trim();
    if (id.isEmpty || normalizedType != 'epub') return null;
    if (_driveCoverMisses.contains(id)) return null;

    final directory = await getApplicationDocumentsDirectory();
    final coverDirectory = Directory('${directory.path}/drive_covers');
    await coverDirectory.create(recursive: true);
    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final coverFile = File('${coverDirectory.path}/$safeId.jpg');
    if (await coverFile.exists() && await coverFile.length() > 0) {
      return coverFile.path;
    }

    return _driveCoverTasks.putIfAbsent(id, () async {
      try {
        final bytes = await GoogleDriveService.downloadFileBytes(
          id,
          maxBytes: _maxDriveCoverDownloadBytes,
        );
        final savedPath = await _writeEpubCover(bytes, coverFile);
        if (savedPath.isEmpty) {
          _driveCoverMisses.add(id);
          return null;
        }
        return savedPath;
      } catch (e) {
        debugPrint('Khong the trich bia EPUB tu Drive: $e');
        _driveCoverMisses.add(id);
        return null;
      } finally {
        _driveCoverTasks.remove(id);
      }
    });
  }

  static Future<String> _writeEpubCover(
    Uint8List bytes,
    File outputFile,
  ) async {
    final coverBytes = await _extractEpubCoverJpgBytes(bytes);
    if (coverBytes == null || coverBytes.isEmpty) return '';

    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes(coverBytes, flush: true);
    return outputFile.path;
  }

  static Future<Uint8List?> _extractEpubCoverJpgBytes(Uint8List bytes) async {
    try {
      final document = await EpubDocument.openData(bytes);
      final coverImage = document.CoverImage;
      if (coverImage != null) {
        return Uint8List.fromList(img.encodeJpg(coverImage, quality: 88));
      }
    } catch (_) {}

    final rawCoverBytes = _extractEpubCoverBytesFromArchive(bytes);
    if (rawCoverBytes == null || rawCoverBytes.isEmpty) return null;

    final decodedImage = img.decodeImage(rawCoverBytes);
    if (decodedImage == null) return null;
    return Uint8List.fromList(img.encodeJpg(decodedImage, quality: 88));
  }

  static Uint8List? _extractEpubCoverBytesFromArchive(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final containerFile = _findArchiveFile(archive, 'META-INF/container.xml');
      String? opfPath;

      if (containerFile != null) {
        final containerText = _archiveFileText(containerFile);
        final containerDocument = XmlDocument.parse(containerText);
        for (final rootFile in containerDocument.findAllElements('rootfile')) {
          final fullPath = rootFile.getAttribute('full-path')?.trim();
          if (fullPath != null && fullPath.isNotEmpty) {
            opfPath = _normalizeZipPath(fullPath);
            break;
          }
        }
      }

      opfPath ??= archive.files
          .map((file) => _normalizeZipPath(file.name))
          .firstWhere(
            (name) => name.toLowerCase().endsWith('.opf'),
            orElse: () => '',
          );
      if (opfPath.isEmpty) return null;

      final opfFile = _findArchiveFile(archive, opfPath);
      if (opfFile == null) return null;

      final opfText = _archiveFileText(opfFile);
      final opfDocument = XmlDocument.parse(opfText);
      final opfBasePath = _zipDirName(opfPath);
      final manifestItems = opfDocument.findAllElements('item').toList();
      final coverCandidates = <String>[];

      String? coverId;
      for (final meta in opfDocument.findAllElements('meta')) {
        final name = meta.getAttribute('name')?.trim().toLowerCase();
        if (name == 'cover') {
          coverId = meta.getAttribute('content')?.trim();
          break;
        }
      }

      if (coverId != null && coverId.isNotEmpty) {
        final coverItem = manifestItems.cast<XmlElement?>().firstWhere(
          (item) => item?.getAttribute('id') == coverId,
          orElse: () => null,
        );
        _addManifestCoverCandidate(coverCandidates, opfBasePath, coverItem);
      }

      for (final item in manifestItems) {
        final properties = item.getAttribute('properties') ?? '';
        if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
          _addManifestCoverCandidate(coverCandidates, opfBasePath, item);
        }
      }

      for (final item in manifestItems) {
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (_looksLikeCoverImage(href, mediaType)) {
          _addManifestCoverCandidate(coverCandidates, opfBasePath, item);
        }
      }

      for (final item in manifestItems) {
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (mediaType.contains('xhtml') &&
            href.toLowerCase().contains('cover')) {
          final coverPagePath = _resolveZipPath(opfBasePath, href);
          final imagePath = _readCoverImagePathFromXhtml(
            archive,
            coverPagePath,
          );
          if (imagePath != null) coverCandidates.add(imagePath);
        }
      }

      for (final item in manifestItems) {
        final href = item.getAttribute('href') ?? '';
        final mediaType = item.getAttribute('media-type') ?? '';
        if (_isImageManifestItem(href, mediaType)) {
          _addManifestCoverCandidate(coverCandidates, opfBasePath, item);
        }
      }

      final seen = <String>{};
      for (final candidate in coverCandidates) {
        final normalized = _normalizeZipPath(candidate);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        final file = _findArchiveFile(archive, normalized);
        if (file == null || file.isFile == false || file.size <= 0) continue;
        return Uint8List.fromList(file.content as List<int>);
      }
    } catch (e) {
      debugPrint('Khong the doc cover EPUB thu cong: $e');
    }

    return null;
  }

  static void _addManifestCoverCandidate(
    List<String> candidates,
    String opfBasePath,
    XmlElement? item,
  ) {
    final href = item?.getAttribute('href')?.trim();
    if (href == null || href.isEmpty) return;
    candidates.add(_resolveZipPath(opfBasePath, href));
  }

  static String? _readCoverImagePathFromXhtml(
    Archive archive,
    String xhtmlPath,
  ) {
    final xhtmlFile = _findArchiveFile(archive, xhtmlPath);
    if (xhtmlFile == null) return null;

    try {
      final document = XmlDocument.parse(_archiveFileText(xhtmlFile));
      for (final image in document.findAllElements('img')) {
        final src = image.getAttribute('src')?.trim();
        if (src != null && src.isNotEmpty) {
          return _resolveZipPath(_zipDirName(xhtmlPath), src);
        }
      }
      for (final image in document.findAllElements('image')) {
        final src =
            image.getAttribute('href') ??
            image.getAttribute('xlink:href') ??
            image.getAttribute('src');
        if (src != null && src.trim().isNotEmpty) {
          return _resolveZipPath(_zipDirName(xhtmlPath), src.trim());
        }
      }
    } catch (_) {}

    return null;
  }

  static bool _looksLikeCoverImage(String href, String mediaType) {
    if (!_isImageManifestItem(href, mediaType)) return false;
    final name = _zipBaseName(href).toLowerCase();
    return name.startsWith('cover.') ||
        name.startsWith('folder.') ||
        name.startsWith('poster.') ||
        name.startsWith('front.') ||
        name.contains('cover') ||
        name.contains('poster');
  }

  static bool _isImageManifestItem(String href, String mediaType) {
    final lowerHref = href.toLowerCase();
    final lowerMediaType = mediaType.toLowerCase();
    return lowerMediaType.startsWith('image/') ||
        lowerHref.endsWith('.jpg') ||
        lowerHref.endsWith('.jpeg') ||
        lowerHref.endsWith('.png') ||
        lowerHref.endsWith('.webp');
  }

  static ArchiveFile? _findArchiveFile(Archive archive, String path) {
    final normalizedPath = _normalizeZipPath(path).toLowerCase();
    for (final file in archive.files) {
      if (_normalizeZipPath(file.name).toLowerCase() == normalizedPath) {
        return file;
      }
    }
    return null;
  }

  static String _archiveFileText(ArchiveFile file) {
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  static String _resolveZipPath(String basePath, String href) {
    final cleanHref = Uri.decodeFull(
      href.split('#').first.split('?').first,
    ).replaceAll('\\', '/');
    if (cleanHref.startsWith('/')) {
      return _normalizeZipPath(cleanHref.substring(1));
    }

    final parts = <String>[
      ..._normalizeZipPath(
        basePath,
      ).split('/').where((part) => part.isNotEmpty),
      ...cleanHref.split('/'),
    ];
    final normalized = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (normalized.isNotEmpty) normalized.removeLast();
      } else {
        normalized.add(part);
      }
    }
    return normalized.join('/');
  }

  static String _normalizeZipPath(String value) {
    return value.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
  }

  static String _zipDirName(String path) {
    final normalized = _normalizeZipPath(path);
    final index = normalized.lastIndexOf('/');
    if (index == -1) return '';
    return normalized.substring(0, index);
  }

  static String _zipBaseName(String path) {
    final normalized = _normalizeZipPath(path);
    final index = normalized.lastIndexOf('/');
    if (index == -1) return normalized;
    return normalized.substring(index + 1);
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
    final stories = localStoriesJson
        .map((s) => Story.fromJson(json.decode(s)))
        .toList();
    return _repairMissingLocalEpubCovers(prefs, stories);
  }

  static Future<List<Story>> _repairMissingLocalEpubCovers(
    SharedPreferences prefs,
    List<Story> stories,
  ) async {
    var changed = false;
    final repairedStories = <Story>[];

    for (final story in stories) {
      var repairedStory = story;
      if (await _shouldRepairLocalEpubCover(story)) {
        try {
          final metadata = await extractEpubMetadata(story.localPath);
          final coverPath = metadata['coverPath'];
          if (coverPath is String && coverPath.isNotEmpty) {
            repairedStory = story.copyWith(iconUrl: coverPath);
            changed = true;
          } else {
            _localCoverRepairMisses.add(story.localPath);
          }
        } catch (e) {
          debugPrint('Khong the khoi phuc bia EPUB local: $e');
          _localCoverRepairMisses.add(story.localPath);
        }
      }
      repairedStories.add(repairedStory);
    }

    if (changed) {
      await prefs.setStringList(
        _localStoriesKey,
        repairedStories.map((story) => json.encode(story.toJson())).toList(),
      );
    }

    return repairedStories;
  }

  static Future<bool> _shouldRepairLocalEpubCover(Story story) async {
    final localPath = story.localPath.trim();
    if (localPath.isEmpty || _localCoverRepairMisses.contains(localPath)) {
      return false;
    }

    final fileType = story.fileType.trim().toLowerCase();
    final isEpub =
        fileType == 'epub' || localPath.toLowerCase().endsWith('.epub');
    if (!isEpub || !await File(localPath).exists()) return false;

    final iconPath = story.iconUrl.trim();
    if (iconPath.isEmpty || iconPath.startsWith('assets/')) return true;
    if (iconPath.startsWith('http')) return false;
    return !await File(iconPath).exists();
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
        iconUrl: updatedStory.iconUrl.isNotEmpty
            ? updatedStory.iconUrl
            : existingStory.iconUrl,
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
