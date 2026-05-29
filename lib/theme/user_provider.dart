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
  }

  Future<void> registerWithBackend({
    required String email,
    required String password,
    required String displayName,
    required int colorValue,
  }) async {
    final user = await ApiService.registerWithBackend(
      email: email,
      password: password,
      displayName: displayName,
    );
    await _setBackendUser(user, colorValue);
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
    notifyListeners();
  }

  @Deprecated('Dùng registerWithBackend/loginWithBackend để đăng nhập thật.')
  Future<void> login(String name, int colorValue) async {
    _name = name.trim();
    _avatarColorValue = colorValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _name);
    await prefs.setInt(_avatarColorKey, colorValue);
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

  // Lấy chữ cái đầu viết hoa để hiển thị avatar
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
