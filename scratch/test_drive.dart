// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const apiKey = String.fromEnvironment('GOOGLE_DRIVE_API_KEY');
  if (apiKey.isEmpty) {
    print('Run with -DGOOGLE_DRIVE_API_KEY=your_key');
    return;
  }

  const folderId = '1-t-i30vQQYyP0sJ7ndTkW8gOrCchZ7f6';
  final String apiUrl =
      'https://www.googleapis.com/drive/v3/files?q=\'$folderId\'+in+parents+and+trashed=false&fields=files(id,name,mimeType)&key=$apiKey';

  print('Fetching root folder...');
  final response = await http.get(Uri.parse(apiUrl));
  final data = json.decode(response.body);
  final List<dynamic> items = data['files'];
  print('Root folder items: ${items.length}');

  for (var item in items) {
    final name = item['name'] as String;
    final id = item['id'] as String;
    final mimeType = item['mimeType'] as String;

    if (mimeType == 'application/vnd.google-apps.folder') {
      print('Found folder: $name ($id)');
      final subApiUrl =
          'https://www.googleapis.com/drive/v3/files?q=\'$id\'+in+parents+and+trashed=false&fields=files(id,name)&key=$apiKey';
      final subResponse = await http.get(Uri.parse(subApiUrl));
      if (subResponse.statusCode == 200) {
        final subData = json.decode(subResponse.body);
        final List<dynamic> subFiles = subData['files'];
        for (var subFile in subFiles) {
          final subName = subFile['name'] as String;
          if (subName.endsWith('.epub') ||
              subName.endsWith('.pdf') ||
              subName.endsWith('.txt')) {
            print('  -> Found story file: $subName');
          }
        }
      } else {
        print('Error fetching subfolder: ${subResponse.body}');
      }
    }
  }
}
