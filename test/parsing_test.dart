import 'package:flutter_test/flutter_test.dart';
import 'package:photo_size/models/photo_item.dart';

/// 这里只测纯逻辑：原生通道传过来的扁平数组怎么解析、大小怎么分组。
/// 这两块一旦错位，界面上表现是「大小全是 0」或「分组全乱」，很难靠肉眼发现。
void main() {
  test('PhotoItem.fromRow 按下标解析', () {
    final item = PhotoItem.fromRow(<dynamic>[
      'ABC/L0/001',
      1700000000.0,
      1700000100.0,
      4032,
      3024,
      0.0,
      1,
      1,
      0,
      0,
      'IMG_0001.HEIC',
      5242880,
      1,
      'meta',
    ]);

    expect(item.id, 'ABC/L0/001');
    expect(item.width, 4032);
    expect(item.height, 3024);
    expect(item.isLive, isTrue);
    expect(item.isFavorite, isFalse);
    expect(item.kind, MediaKind.photo);
    expect(item.sizeLabel, '5.0 MB');
    expect(item.bytesKnown, isTrue);
  });

  test('缺字段不会崩', () {
    final item = PhotoItem.fromRow(<dynamic>['only-id']);
    expect(item.id, 'only-id');
    expect(item.bytesKnown, isFalse);
    expect(item.sizeLabel, '…');
  });

  test('大小分组边界', () {
    expect(SizeBucket.forBytes(0), SizeBucket.unknown);
    expect(SizeBucket.forBytes(1024), SizeBucket.under100kb);
    expect(SizeBucket.forBytes(100 * 1024), SizeBucket.from100kb);
    expect(SizeBucket.forBytes(1024 * 1024), SizeBucket.from1to5);
    expect(SizeBucket.forBytes(5 * 1024 * 1024), SizeBucket.from5to10);
    expect(SizeBucket.forBytes(150 * 1024 * 1024), SizeBucket.over100mb);
  });
}
