// Script kiểm tra metadata EPUB
// Chạy: dart run scratch/check_epub_metadata.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:epubx/epubx.dart' as epubx;

Future<void> main() async {
  final files = [
    r'assets\offline_stories\15136.epub',
    r'assets\offline_stories\18301.epub',
    r'assets\offline_stories\ThanhXuan_Vol1.epub',
    r'assets\offline_stories\ThanhXuan_Vol2.epub',
  ];

  for (final path in files) {
    print('─' * 60);
    print('File: $path');
    try {
      final bytes = await File(path).readAsBytes();
      final book = await epubx.EpubReader.readBook(bytes);

      print('  Title     : ${book.Title}');
      print('  Author    : ${book.Author}');
      print('  AuthorList: ${book.AuthorList}');

      // Schema / metadata thêm
      final schema = book.Schema;
      if (schema != null) {
        final pkg = schema.Package;
        if (pkg != null) {
          final meta = pkg.Metadata;
          if (meta != null) {
            print('  Subjects  : ${meta.Subjects}');
            print('  Publishers: ${meta.Publishers}');
            print('  Languages : ${meta.Languages}');
            print(
              '  Description: ${meta.Description?.substring(0, meta.Description!.length > 200 ? 200 : meta.Description!.length)}...',
            );
            print('  Contributors: ${meta.Contributors}');
            // In tất cả MetaItems (custom metadata)
            if (meta.MetaItems != null && meta.MetaItems!.isNotEmpty) {
              print('  MetaItems:');
              for (final item in meta.MetaItems!) {
                print('    name="${item.Name}" content="${item.Content}"');
              }
            }
          }
        }
      }
    } catch (e) {
      print('  LỖI: $e');
    }
  }
  print('─' * 60);
}
