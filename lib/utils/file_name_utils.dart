import 'dart:convert';

class FileNameUtils {
  static String normalizeExtension(String value, {String fallback = 'epub'}) {
    final cleaned = value
        .replaceAll('.', '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase()
        .trim();
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 10 ? cleaned.substring(0, 10) : cleaned;
  }

  static String safeStem(
    String value, {
    String fallback = 'file',
    int maxBytes = 120,
  }) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'_+'), '_')
        .trim()
        .replaceAll(RegExp(r'^[ ._]+|[ ._]+$'), '');

    final base = cleaned.isEmpty ? fallback : cleaned;
    final limited = _limitUtf8Bytes(
      base,
      maxBytes,
    ).replaceAll(RegExp(r'^[ ._]+|[ ._]+$'), '');
    return limited.isEmpty ? fallback : limited;
  }

  static String storageFileName({
    required String title,
    required String uniqueId,
    required String extension,
  }) {
    final ext = normalizeExtension(extension);
    final titlePart = safeStem(title, fallback: 'story', maxBytes: 80);
    final idPart = safeStem(
      uniqueId.replaceAll(RegExp(r'\s+'), '_'),
      fallback: DateTime.now().microsecondsSinceEpoch.toString(),
      maxBytes: 48,
    );
    final stem = safeStem(
      '$titlePart-$idPart',
      fallback: idPart,
      maxBytes: 150,
    );
    return '$stem.$ext';
  }

  static String _limitUtf8Bytes(String value, int maxBytes) {
    if (utf8.encode(value).length <= maxBytes) return value;

    final buffer = StringBuffer();
    var usedBytes = 0;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      final byteLength = utf8.encode(char).length;
      if (usedBytes + byteLength > maxBytes) break;
      buffer.write(char);
      usedBytes += byteLength;
    }
    return buffer.toString().trimRight();
  }
}
