import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_config.dart';
import '../models/app_user.dart';
import '../models/community_message.dart';
import '../models/story.dart';

class FirebaseBackendService {
  static bool _initialized = false;

  static bool get isConfigured =>
      VBookFirebaseConfig.isConfigured || _canUseNativeAndroidConfig;
  static bool get isInitialized => _initialized;

  static bool get _canUseNativeAndroidConfig =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static firebase_auth.FirebaseAuth get _auth =>
      firebase_auth.FirebaseAuth.instance;

  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint(
        'Đồng bộ tài khoản chưa được cấu hình. Đăng nhập và chat sẽ tạm tắt trong bản chạy hiện tại.',
      );
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        if (VBookFirebaseConfig.isConfigured) {
          await Firebase.initializeApp(
            options: VBookFirebaseConfig.currentPlatform,
          );
        } else {
          await Firebase.initializeApp();
        }
      }
      _initialized = true;
    } catch (e) {
      _initialized = false;
      debugPrint('Không thể khởi tạo đồng bộ tài khoản: $e');
    }
  }

  static void _ensureReady() {
    if (!_initialized) {
      throw Exception(
        'Chưa bật đồng bộ tài khoản. Hãy kiểm tra cấu hình dịch vụ trước khi đăng nhập.',
      );
    }
  }

  static bool isAdminEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return VBookFirebaseConfig.adminEmails.contains(normalized);
  }

  static Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _ensureReady();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Không thể tạo tài khoản mới. Vui lòng thử lại.');
      }

      await user.updateDisplayName(displayName);
      await user.reload();
      final refreshedUser = _auth.currentUser ?? user;
      await _upsertProfile(refreshedUser, displayName: displayName);
      await refreshedUser.sendEmailVerification();
      return _appUserFromFirebase(refreshedUser);
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    }
  }

  static Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    _ensureReady();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Không thể mở phiên đăng nhập. Vui lòng thử lại.');
      }

      await user.reload();
      final refreshedUser = _auth.currentUser ?? user;
      if (!refreshedUser.emailVerified) {
        await refreshedUser.sendEmailVerification();
        throw Exception(
          'Email chưa xác nhận. Hệ thống đã gửi lại link xác nhận vào email của bạn.',
        );
      }

      await _refreshVerifiedToken(refreshedUser);
      await _upsertProfile(refreshedUser);
      return _appUserFromFirebase(refreshedUser);
    } on firebase_auth.FirebaseAuthException catch (e) {
      throw Exception(_authErrorMessage(e));
    }
  }

  static Future<AppUser> confirmEmailVerified({required String email}) async {
    _ensureReady();
    final user = _auth.currentUser;
    if (user == null ||
        (user.email ?? '').toLowerCase() != email.toLowerCase()) {
      throw Exception(
        'Hãy đăng nhập lại bằng email vừa đăng ký, sau đó bấm link xác nhận trong hộp thư.',
      );
    }

    await user.reload();
    final refreshedUser = _auth.currentUser ?? user;
    if (!refreshedUser.emailVerified) {
      throw Exception(
        'Email vẫn chưa được xác nhận. Hãy mở email và bấm link xác nhận.',
      );
    }

    await _refreshVerifiedToken(refreshedUser);
    await _upsertProfile(refreshedUser);
    return _appUserFromFirebase(refreshedUser);
  }

  static Future<void> resendVerificationEmail({required String email}) async {
    _ensureReady();
    final user = _auth.currentUser;
    if (user == null ||
        (user.email ?? '').toLowerCase() != email.toLowerCase()) {
      throw Exception(
        'Hãy đăng nhập lại bằng email này để hệ thống gửi lại link xác nhận.',
      );
    }
    await user.sendEmailVerification();
  }

  static Future<AppUser?> refreshCurrentUser() async {
    if (!_initialized) return null;
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null || !refreshedUser.emailVerified) return null;
      await _refreshVerifiedToken(refreshedUser);
      await _upsertProfile(refreshedUser);
      return _appUserFromFirebase(refreshedUser);
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Không thể làm mới phiên đăng nhập: ${_authErrorMessage(e)}');
      return null;
    }
  }

  static Future<String?> currentSessionToken() async {
    if (!_initialized) return null;
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return null;
    await _refreshVerifiedToken(user);
    return user.uid;
  }

  static Future<void> logout() async {
    if (_initialized) {
      await _auth.signOut();
    }
  }

  static Future<List<CommunityMessage>> fetchCommunityMessages() async {
    _ensureReady();
    final snapshot = await _db
        .collection('community_messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.reversed.map(_messageFromDoc).toList();
  }

  static Future<CommunityMessage> sendCommunityMessage(String text) async {
    _ensureReady();
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Cần đăng nhập và xác nhận email để gửi tin nhắn.');
    }

    await user.reload();
    final refreshedUser = _auth.currentUser ?? user;
    if (!refreshedUser.emailVerified) {
      throw Exception(
        'Cáº§n Ä‘Äƒng nháº­p vÃ  xÃ¡c nháº­n email Ä‘á»ƒ gá»­i tin nháº¯n.',
      );
    }

    await _refreshVerifiedToken(refreshedUser);
    final appUser = await _appUserFromFirebase(refreshedUser);
    final ref = await _db.collection('community_messages').add({
      'userId': appUser.id,
      'displayName': appUser.displayName,
      'avatarUrl': appUser.avatarUrl,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return _messageFromDoc(doc);
  }

  static Future<void> syncStoryToLibrary(Story story) async {
    if (!_initialized) return;
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(story.id)
        .set({
          'storyId': story.id,
          'story': story.toJson(),
          'savedChapterIndex': story.savedChapterIndex,
          'totalChapters': story.totalChapters,
          'scrollOffset': 0,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  static Future<void> syncProgress(
    String storyId,
    int chapterIndex, {
    int? totalChapters,
    double? scrollOffset,
  }) async {
    if (!_initialized) return;
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return;

    final payload = <String, dynamic>{
      'savedChapterIndex': chapterIndex,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastReadAt': FieldValue.serverTimestamp(),
    };
    if (totalChapters != null) {
      payload['totalChapters'] = totalChapters;
    }
    if (scrollOffset != null) {
      payload['scrollOffset'] = scrollOffset;
    }

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(storyId)
        .set(payload, SetOptions(merge: true));
  }

  static Future<void> removeStoryFromLibrary(String storyId) async {
    if (!_initialized) return;
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .doc(storyId)
        .delete();
  }

  static Future<List<Story>> fetchCloudLibraryStories() async {
    if (!_initialized) return [];
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return [];

    final snapshot = await _db
        .collection('users')
        .doc(user.uid)
        .collection('library')
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) {
          final data = doc.data();
          final rawStory = data['story'];
          if (rawStory is! Map) return null;
          final story = Story.fromJson(Map<String, dynamic>.from(rawStory));
          return story.copyWith(
            savedChapterIndex: _readInt(data['savedChapterIndex']),
            totalChapters: _readInt(data['totalChapters'], story.totalChapters),
          );
        })
        .whereType<Story>()
        .toList();
  }

  static Future<void> _upsertProfile(
    firebase_auth.User user, {
    String? displayName,
  }) async {
    final ref = _db.collection('users').doc(user.uid);
    final snapshot = await ref.get();
    final existing = snapshot.data();
    final email = user.email ?? '';
    final role = existing?['role']?.toString() ?? 'user';
    final name = (displayName ?? user.displayName ?? email.split('@').first)
        .trim();

    final data = {
      'uid': user.uid,
      'email': email,
      'displayName': name.isEmpty ? email.split('@').first : name,
      'avatarUrl': user.photoURL ?? '',
      'role': role,
      'emailVerified': user.emailVerified,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (snapshot.exists) {
      await ref.set(data, SetOptions(merge: true));
    } else {
      await ref.set({...data, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  static Future<void> _refreshVerifiedToken(firebase_auth.User user) async {
    if (!user.emailVerified) return;
    await user.getIdToken(true);
  }

  static Future<AppUser> _appUserFromFirebase(firebase_auth.User user) async {
    Map<String, dynamic>? profile;
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      profile = doc.data();
    } catch (_) {}

    final email = user.email ?? profile?['email']?.toString() ?? '';
    final displayName =
        profile?['displayName']?.toString() ??
        user.displayName ??
        email.split('@').first;
    final role = isAdminEmail(email)
        ? 'admin'
        : profile?['role']?.toString() ?? 'user';

    return AppUser(
      id: user.uid,
      email: email,
      displayName: displayName,
      avatarUrl: profile?['avatarUrl']?.toString() ?? user.photoURL ?? '',
      role: role,
      emailVerified: user.emailVerified,
    );
  }

  static CommunityMessage _messageFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return CommunityMessage.fromJson({
      'id': doc.id,
      'userId': data['userId'],
      'displayName': data['displayName'],
      'avatarUrl': data['avatarUrl'],
      'text': data['text'],
      'createdAt': _timestampToIso(data['createdAt']),
    });
  }

  static String _timestampToIso(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    return value?.toString() ?? '';
  }

  static int _readInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _authErrorMessage(firebase_auth.FirebaseAuthException e) {
    return switch (e.code) {
      'email-already-in-use' => 'Email này đã được đăng ký.',
      'invalid-email' => 'Email không hợp lệ.',
      'weak-password' => 'Mật khẩu quá yếu, hãy dùng ít nhất 6 ký tự.',
      'user-not-found' => 'Không tìm thấy tài khoản với email này.',
      'wrong-password' => 'Mật khẩu không đúng.',
      'invalid-credential' => 'Email hoặc mật khẩu không đúng.',
      'too-many-requests' => 'Đăng nhập quá nhiều lần. Hãy thử lại sau.',
      _ => e.message ?? 'Lỗi đăng nhập: ${e.code}',
    };
  }
}
