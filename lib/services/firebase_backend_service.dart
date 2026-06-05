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

  static bool get isConfigured => VBookFirebaseConfig.isConfigured;
  static bool get isInitialized => _initialized;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static firebase_auth.FirebaseAuth get _auth =>
      firebase_auth.FirebaseAuth.instance;

  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint(
        'Dong bo tai khoan chua duoc cau hinh. Dang nhap/chat se bi tat cho den khi them FIREBASE_* dart-define.',
      );
      return;
    }

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: VBookFirebaseConfig.currentPlatform,
      );
    }
    _initialized = true;
  }

  static void _ensureReady() {
    if (!_initialized) {
      throw Exception(
        'Chua bat dong bo tai khoan. Hay kiem tra cau hinh dich vu truoc khi dang nhap.',
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
        throw Exception('Khong the tao tai khoan moi. Vui long thu lai.');
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
        throw Exception('Khong the mo phien dang nhap. Vui long thu lai.');
      }

      await user.reload();
      final refreshedUser = _auth.currentUser ?? user;
      if (!refreshedUser.emailVerified) {
        await refreshedUser.sendEmailVerification();
        throw Exception(
          'Email chua xac nhan. He thong da gui lai link xac nhan vao email cua ban.',
        );
      }

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
        'Hay dang nhap lai bang email vua dang ky, sau do bam link xac nhan trong hop thu.',
      );
    }

    await user.reload();
    final refreshedUser = _auth.currentUser ?? user;
    if (!refreshedUser.emailVerified) {
      throw Exception(
        'Email van chua duoc xac nhan. Hay mo email va bam link xac nhan.',
      );
    }

    await _upsertProfile(refreshedUser);
    return _appUserFromFirebase(refreshedUser);
  }

  static Future<void> resendVerificationEmail({required String email}) async {
    _ensureReady();
    final user = _auth.currentUser;
    if (user == null ||
        (user.email ?? '').toLowerCase() != email.toLowerCase()) {
      throw Exception(
        'Hay dang nhap lai bang email nay de he thong gui lai link xac nhan.',
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
      await _upsertProfile(refreshedUser);
      return _appUserFromFirebase(refreshedUser);
    } on firebase_auth.FirebaseAuthException catch (e) {
      debugPrint('Khong the lam moi phien dang nhap: ${_authErrorMessage(e)}');
      return null;
    }
  }

  static Future<String?> currentSessionToken() async {
    if (!_initialized) return null;
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) return null;
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
    if (user == null || !user.emailVerified) {
      throw Exception('Can dang nhap va xac nhan email de gui tin nhan.');
    }

    final appUser = await _appUserFromFirebase(user);
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
      'email-already-in-use' => 'Email nay da duoc dang ky.',
      'invalid-email' => 'Email khong hop le.',
      'weak-password' => 'Mat khau qua yeu, hay dung it nhat 6 ky tu.',
      'user-not-found' => 'Khong tim thay tai khoan voi email nay.',
      'wrong-password' => 'Mat khau khong dung.',
      'invalid-credential' => 'Email hoac mat khau khong dung.',
      'too-many-requests' => 'Dang nhap qua nhieu lan. Hay thu lai sau.',
      _ => e.message ?? 'Loi dang nhap: ${e.code}',
    };
  }
}
