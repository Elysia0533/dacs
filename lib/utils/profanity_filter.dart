/// Bộ lọc từ ngữ không phù hợp.
/// Chỉ lọc các từ bậy đứng độc lập hoàn toàn (word boundary),
/// KHÔNG lọc nếu từ bậy nằm bên trong một từ khác (ví dụ: "admin" không bị lọc vì chứa "ad").
class ProfanityFilter {
  ProfanityFilter._();

  /// Danh sách từ/cụm từ bậy rõ ràng - CHỈ bao gồm những từ chắc chắn là bậy
  static const List<String> _badWords = [
    // Tiếng Việt - có dấu (từ hoàn chỉnh)
    'đụ', 'địt', 'cặc', 'lồn', 'đéo', 'đĩ',
    'đm', 'đmm', 'đmcs', 'đcm',
    'vãi lồn', 'vkl', 'vcl',
    'clgt',
    'óc chó',
    'khốn nạn',
    'đồ khốn',
    'chó chết',
    'đồ chó',
    'con chó',
    'thằng chó',
    'thằng điên',
    // Tiếng Việt không dấu
    'dit me', 'dit con', 'du ma', 'du me',
    'dm', 'dcm', 'vkl', 'vcl', 'clgt', 'dmm', 'dkm',
    // Tiếng Anh - rõ ràng
    'fuck', 'fucker', 'fucking', 'fucked', 'fck',
    'shit', 'shitting',
    'bitch', 'bitching',
    'asshole',
    'bastard',
    'cunt',
    'wtf', 'stfu',
  ];

  // Cache các regex đã biên dịch để tăng hiệu suất
  static final Map<String, RegExp> _regexCache = {};

  static RegExp _getRegex(String word) {
    return _regexCache.putIfAbsent(word, () {
      final escaped = RegExp.escape(word);
      // \b không hoạt động tốt với Unicode tiếng Việt nên dùng lookahead/lookbehind
      // Đảm bảo từ không nằm giữa các chữ cái khác
      return RegExp(
        r'(?<![a-zA-ZÀ-ỹа-яА-Я\d])' + escaped + r'(?![a-zA-ZÀ-ỹа-яА-Я\d])',
        caseSensitive: false,
        unicode: true,
      );
    });
  }

  /// Lọc và thay thế từ bậy bằng dấu ***
  static String filter(String text) {
    if (text.isEmpty) return text;

    String result = text;
    for (final word in _badWords) {
      final regex = _getRegex(word);
      result = result.replaceAllMapped(regex, (match) {
        return '*' * match.group(0)!.length;
      });
    }
    return result;
  }

  /// Kiểm tra xem văn bản có chứa từ bậy không
  static bool containsProfanity(String text) {
    if (text.isEmpty) return false;
    for (final word in _badWords) {
      if (_getRegex(word).hasMatch(text)) return true;
    }
    return false;
  }
}
