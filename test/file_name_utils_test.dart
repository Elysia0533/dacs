import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:online_story_reader/utils/file_name_utils.dart';

void main() {
  test('storageFileName keeps long translated titles within Android limits', () {
    final fileName = FileNameUtils.storageFileName(
      title:
          'Chuyen Tinh Yeu Chi Muon Hoi Ho Mot Nguoi Ban, Nhung Co Ban Thu Nho De Boi Roi Cua Toi Cu Lien Tuc The Hien Rang Co Ay Yeu Toi! - QUYEN 1 DA HOAN THANH',
      uniqueId: '1aBcDeFgHiJkLmNoPqRsTuVwXyZ',
      extension: 'epub',
    );

    expect(fileName.endsWith('.epub'), isTrue);
    expect(fileName.contains(RegExp(r'[\\/:*?"<>|]')), isFalse);
    expect(utf8.encode(fileName).length, lessThanOrEqualTo(160));
  });

  test('storageFileName handles multi-byte titles safely', () {
    final fileName = FileNameUtils.storageFileName(
      title:
          'Mot lan nua song lai thanh xuan '
          'm\u00f9a h\u1ea1 r\u1ef1c r\u1ee1 b\u00ean '
          'ng\u01b0\u1eddi c\u00f4 \u0111\u01a1n '
          '\u3082\u3046\u4e00\u5ea6\u9752\u6625\u3092'
          '\u3084\u308a\u76f4\u3059\u7269\u8a9e',
      uniqueId: 'drive-file-id',
      extension: '.PDF',
    );

    expect(fileName.endsWith('.pdf'), isTrue);
    expect(utf8.encode(fileName).length, lessThanOrEqualTo(160));
  });
}
