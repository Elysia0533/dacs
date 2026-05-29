import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/story.dart';
import 'package:uuid/uuid.dart';

class GoogleDriveService {
  static const String apiKey = String.fromEnvironment('GOOGLE_DRIVE_API_KEY');

  static String? extractFolderId(String url) {
    // Ví dụ URL: https://drive.google.com/drive/folders/1JqHqueAhOcybtFQixX1PTypmq0MB7Mrx
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.contains('folders')) {
      final index = uri.pathSegments.indexOf('folders');
      if (index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }
    return null;
  }

  static Future<List<Story>> fetchStoriesFromFolder(String folderUrl) async {
    final folderId = extractFolderId(folderUrl);
    if (folderId == null) {
      throw Exception('URL thư mục không hợp lệ');
    }

    if (apiKey.isEmpty) {
      throw Exception(
        'Vui lòng cung cấp GOOGLE_DRIVE_API_KEY bằng --dart-define',
      );
    }

    final String apiUrl =
        'https://www.googleapis.com/drive/v3/files?q=\'$folderId\'+in+parents+and+trashed=false&fields=files(id,name,mimeType,thumbnailLink)&key=$apiKey';

    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['files'];
      List<Story> stories = [];

      for (var item in items) {
        final name = item['name'] as String;
        final id = item['id'] as String;
        final mimeType = item['mimeType'] as String;
        final folderThumbnail = (item['thumbnailLink'] as String?) ?? '';

        if (mimeType == 'application/vnd.google-apps.folder') {
          // Nếu là thư mục, tên thư mục sẽ là tên truyện
          // Gọi API để tìm file epub/txt bên trong thư mục này
          final subApiUrl =
              'https://www.googleapis.com/drive/v3/files?q=\'$id\'+in+parents+and+trashed=false&fields=files(id,name,thumbnailLink)&key=$apiKey';
          final subResponse = await http.get(Uri.parse(subApiUrl));
          if (subResponse.statusCode == 200) {
            final subData = json.decode(subResponse.body);
            final List<dynamic> subFiles = subData['files'];
            for (var subFile in subFiles) {
              final subName = subFile['name'] as String;
              if (subName.endsWith('.epub') ||
                  subName.endsWith('.pdf') ||
                  subName.endsWith('.txt')) {
                // Nếu lấy được file con, ta nối tên thư mục gốc với tên file (bỏ đuôi) để người dùng phân biệt nếu có nhiều vol
                final cleanSubName = subName.replaceAll(
                  RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
                  '',
                );
                final displayTitle = (subFiles.length > 1)
                    ? '$name - $cleanSubName'
                    : name;
                final subThumbnail =
                    (subFile['thumbnailLink'] as String?) ?? '';
                // Ưu tiên thumbnail của sub-file, nếu không có thì dùng của thư mục cha
                final iconUrl = subThumbnail.isNotEmpty
                    ? subThumbnail
                    : folderThumbnail;

                stories.add(
                  Story(
                    id: const Uuid().v4(),
                    title: displayTitle,
                    driveFileId: subFile['id'] as String,
                    isFromDrive: true,
                    isLocal: false,
                    iconUrl: iconUrl,
                  ),
                );
                // Không dùng break nữa để lấy được tất cả các tập (vol) trong 1 bộ truyện
              }
            }
          }
        } else {
          // Chỉ lấy epub, pdf, txt nếu nằm trực tiếp
          if (name.endsWith('.epub') ||
              name.endsWith('.pdf') ||
              name.endsWith('.txt')) {
            // Xóa đuôi mở rộng để lấy tên
            final cleanName = name.replaceAll(
              RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false),
              '',
            );
            stories.add(
              Story(
                id: const Uuid().v4(),
                title: cleanName,
                driveFileId: id,
                isFromDrive: true,
                isLocal: false,
                iconUrl: folderThumbnail,
              ),
            );
          }
        }
      }
      return stories;
    } else {
      throw Exception('Lỗi khi tải thư mục: ${response.body}');
    }
  }

  static String getDownloadUrl(String fileId) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
  }

  static Future<Uint8List> downloadFileBytes(
    String fileId, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception(
        'Vui lòng cung cấp GOOGLE_DRIVE_API_KEY bằng --dart-define',
      );
    }

    final String apiUrl = getDownloadUrl(fileId);
    final request = http.Request('GET', Uri.parse(apiUrl));
    final response = await request.send();

    if (response.statusCode == 200) {
      final chunks = <int>[];
      var receivedBytes = 0;
      final totalBytes = response.contentLength;

      await for (final chunk in response.stream) {
        chunks.addAll(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      return Uint8List.fromList(chunks);
    }

    final errorBody = await response.stream.bytesToString();
    throw Exception('Lỗi khi tải file từ Drive: $errorBody');
  }
}
