import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class VBookFirebaseConfig {
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );
  static const String iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
  );
  static const String adminEmailsRaw = String.fromEnvironment(
    'VBOOK_ADMIN_EMAILS',
  );
  static const String defaultAdminEmailsRaw = 'vglduc25@gmail.com';

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static List<String> get adminEmails => {
    ..._parseEmails(defaultAdminEmailsRaw),
    ..._parseEmails(adminEmailsRaw),
  }.toList();

  static List<String> _parseEmails(String raw) => raw
      .split(RegExp(r'[,;|\s]+'))
      .map((email) => email.trim().toLowerCase())
      .where((email) => email.isNotEmpty)
      .toList();

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Chưa cấu hình đồng bộ tài khoản cho vBook.');
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: kIsWeb || defaultTargetPlatform == TargetPlatform.android
          ? (measurementId.isEmpty ? null : measurementId)
          : null,
      iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
    );
  }
}
