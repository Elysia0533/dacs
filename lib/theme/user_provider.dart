import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../services/api_service.dart';

class UserProvider extends ChangeNotifier {
  static const _nameKey = 'user_name';
  static const _avatarColorKey = 'user_avatar_color';

  AppUser? _user;
  String _name = '';
  String _id = '';
  String _email = '';
  String _role = 'user';
  String _token = '';
  int _avatarColorValue = 0xFF4CAF50;

  String get name => _name;
  String get id => _id;
  String get email => _email;
  String get role => _role;
  String get token => _token;
  bool get isLoggedIn => _user != null && _token.isNotEmpty;
  bool get isAdmin => _role == 'admin';
  bool get emailVerified => _user?.emailVerified ?? false;
  Color get avatarColor => Color(_avatarColorValue);

  UserProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _user = await ApiService.getSavedUser();
    _token = await ApiService.getSavedAuthToken() ?? '';
    _id = _user?.id ?? '';
    _name = _user?.displayName ?? prefs.getString(_nameKey) ?? '';
    _email = _user?.email ?? '';
    _role = _user?.role ?? 'user';
    _avatarColorValue = prefs.getInt(_avatarColorKey) ?? 0xFF4CAF50;
    notifyListeners();

    await refreshSession();
  }

  Future<RegisterResult> registerWithBackend({
    required String email,
    required String password,
    required String displayName,
    required int colorValue,
  }) async {
    final result = await ApiService.registerWithBackend(
      email: email,
      password: password,
      displayName: displayName,
    );
    if (!result.emailVerificationRequired) {
      await _setBackendUser(result.user, colorValue);
    }
    return result;
  }

  Future<void> loginWithBackend({
    required String email,
    required String password,
    required int colorValue,
  }) async {
    final user = await ApiService.loginWithBackend(
      email: email,
      password: password,
    );
    await _setBackendUser(user, colorValue);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return ApiService.sendPasswordResetEmail(email: email);
  }

  Future<void> updateProfile({
    required String displayName,
    required int colorValue,
    String avatarUrl = '',
  }) async {
    final user = await ApiService.updateUserProfile(
      displayName: displayName,
      avatarColorValue: colorValue,
      avatarUrl: avatarUrl,
    );
    _user = user;
    _id = user.id;
    _name = user.displayName;
    _email = user.email;
    _role = user.role;
    _avatarColorValue = colorValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    await prefs.setInt(_avatarColorKey, colorValue);
    notifyListeners();
  }

  Future<void> verifyEmailWithBackend({
    required String email,
    required String code,
    required int colorValue,
  }) async {
    final user = await ApiService.verifyEmailWithBackend(
      email: email,
      code: code,
    );
    await _setBackendUser(user, colorValue);
  }

  Future<EmailVerificationResult> resendVerificationCode(String email) {
    return ApiService.resendVerificationCode(email: email);
  }

  Future<void> _setBackendUser(AppUser user, int colorValue) async {
    _user = user;
    _token = await ApiService.getSavedAuthToken() ?? '';
    _id = user.id;
    _name = user.displayName;
    _email = user.email;
    _role = user.role;
    _avatarColorValue = colorValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    await prefs.setInt(_avatarColorKey, colorValue);
    await ApiService.mergeCloudLibraryIntoLocal();
    notifyListeners();
  }

  Future<void> refreshSession() async {
    final refreshedUser = await ApiService.refreshCurrentUser();
    if (refreshedUser == null) return;

    _user = refreshedUser;
    _token = await ApiService.getSavedAuthToken() ?? _token;
    _id = refreshedUser.id;
    _name = refreshedUser.displayName;
    _email = refreshedUser.email;
    _role = refreshedUser.role;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    await ApiService.mergeCloudLibraryIntoLocal();
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiService.logoutBackend();
    _user = null;
    _id = '';
    _name = '';
    _email = '';
    _role = 'user';
    _token = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_avatarColorKey);
    notifyListeners();
  }

  String get initials {
    if (_name.isEmpty) return '?';
    final parts = _name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return _name[0].toUpperCase();
  }

  static const List<Map<String, dynamic>> avatarColors = [
    {'label': 'Xanh lá', 'value': 0xFF4CAF50},
    {'label': 'Xanh dương', 'value': 0xFF2196F3},
    {'label': 'Tím', 'value': 0xFF9C27B0},
    {'label': 'Cam', 'value': 0xFFFF9800},
    {'label': 'Đỏ', 'value': 0xFFF44336},
    {'label': 'Xanh ngọc', 'value': 0xFF009688},
  ];
}
