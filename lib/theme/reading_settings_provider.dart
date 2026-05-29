import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ReadingSettingsProvider extends ChangeNotifier {
  static const String _fontSizeKey = 'reading_font_size';
  static const String _fontFamilyKey = 'reading_font_family';
  static const String _bgColorKey = 'reading_bg_color';
  static const String _lineHeightKey = 'reading_line_height';

  double _fontSize = 18.0;
  String _fontFamily = 'Merriweather';
  int _bgColorValue = 0xFFF5F0E8; // Kem
  double _lineHeight = 1.7;

  double get fontSize => _fontSize;
  String get fontFamily => _fontFamily;
  Color get bgColor => Color(_bgColorValue);
  double get lineHeight => _lineHeight;

  // Danh sách các font đọc truyện
  static const List<Map<String, String>> availableFonts = [
    {'name': 'Merriweather', 'label': 'Merriweather'},
    {'name': 'Nunito', 'label': 'Nunito'},
    {'name': 'Roboto', 'label': 'Roboto'},
    {'name': 'Lora', 'label': 'Lora'},
    {'name': 'Inter', 'label': 'Inter'},
    {'name': 'PlayfairDisplay', 'label': 'Playfair'},
  ];

  // Danh sách màu nền
  static const List<Map<String, dynamic>> bgColors = [
    {'label': 'Trắng', 'value': 0xFFFFFFFF, 'textColor': 0xFF1A1A1A},
    {'label': 'Vàng nhạt (Sepia)', 'value': 0xFFF4ECD8, 'textColor': 0xFF333333},
    {'label': 'Xanh nhạt', 'value': 0xFFEAF4EA, 'textColor': 0xFF1A2E1A},
    {'label': 'Xám tối', 'value': 0xFF2C2C2C, 'textColor': 0xFFD0D0D0},
    {'label': 'Đen OLED', 'value': 0xFF000000, 'textColor': 0xFFCCCCCC},
  ];

  Color get textColor {
    final match = bgColors.firstWhere(
      (c) => c['value'] == _bgColorValue,
      orElse: () => bgColors[1],
    );
    return Color(match['textColor'] as int);
  }

  TextStyle get bodyTextStyle {
    return _getGoogleFont(_fontFamily).copyWith(
      fontSize: _fontSize,
      height: _lineHeight,
      color: textColor,
    );
  }

  TextStyle _getGoogleFont(String name) {
    switch (name) {
      case 'Nunito':
        return GoogleFonts.nunito();
      case 'Roboto':
        return GoogleFonts.roboto();
      case 'Lora':
        return GoogleFonts.lora();
      case 'Inter':
        return GoogleFonts.inter();
      case 'PlayfairDisplay':
        return GoogleFonts.playfairDisplay();
      case 'Merriweather':
      default:
        return GoogleFonts.merriweather();
    }
  }

  ReadingSettingsProvider() {
    _load();
  }

  void setFontSize(double size) {
    _fontSize = size.clamp(12.0, 28.0);
    notifyListeners();
    _save();
  }

  void setFontFamily(String family) {
    _fontFamily = family;
    notifyListeners();
    _save();
  }

  void setBgColor(int colorValue) {
    _bgColorValue = colorValue;
    notifyListeners();
    _save();
  }

  void setLineHeight(double h) {
    _lineHeight = h.clamp(1.2, 2.2);
    notifyListeners();
    _save();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 18.0;
    _fontFamily = prefs.getString(_fontFamilyKey) ?? 'Merriweather';
    _bgColorValue = prefs.getInt(_bgColorKey) ?? 0xFFF5F0E8;
    _lineHeight = prefs.getDouble(_lineHeightKey) ?? 1.7;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, _fontSize);
    await prefs.setString(_fontFamilyKey, _fontFamily);
    await prefs.setInt(_bgColorKey, _bgColorValue);
    await prefs.setDouble(_lineHeightKey, _lineHeight);
  }
}
