import '../util/format.dart';

/// 媒体种类。原生侧返回的是整数编码，这里映射成有限的几种，
/// 未知值统一按 [MediaKind.other] 处理，界面不会因为新类型崩掉。
enum MediaKind {
  photo(1, '照片'),
  video(2, '视频'),
  audio(3, '音频'),
  other(0, '其他');

  const MediaKind(this.code, this.label);

  final int code;
  final String label;

  bool get isPhoto => this == MediaKind.photo;
  bool get isVideo => this == MediaKind.video;

  static MediaKind fromCode(int code) {
    for (final kind in MediaKind.values) {
      if (kind.code == code) return kind;
    }
    return MediaKind.other;
  }
}

/// 相册里的一个项目（照片 / 视频 / Live Photo）。
///
/// [bytes] 是该资产**所有资源**的合计占用（Live Photo 含配对视频、
/// ProRAW 含 DNG + 渲染图 + 编辑指令），和系统「照片」App 详情里的数字同口径。
class PhotoItem {
  const PhotoItem({
    required this.id,
    required this.created,
    required this.modified,
    required this.width,
    required this.height,
    required this.duration,
    required this.kind,
    required this.isLive,
    required this.isFavorite,
    required this.isHidden,
    required this.filename,
    required this.bytes,
    required this.bytesKnown,
    required this.sizeSource,
  });

  final String id;
  final double created;
  final double modified;
  final int width;
  final int height;
  final double duration;
  final MediaKind kind;
  final bool isLive;
  final bool isFavorite;
  final bool isHidden;
  final String filename;

  /// 合计字节数；0 表示还没算出来
  final int bytes;

  /// 大小是否已经确认（0 字节也是有效值，但相册里不存在 0 字节的资产，
  /// 所以用独立的标志位而不是靠 0 判断）
  final bool bytesKnown;

  /// "meta" = 系统元数据，"read" = 逐文件读取，"partial" = 部分读取成功
  final String sizeSource;

  bool get isVideo => kind == MediaKind.video;

  String get displayName => filename.isEmpty ? kind.label : filename;

  double get megapixels => width * height / 1000000.0;

  String get sizeLabel => bytesKnown ? formatBytes(bytes) : '…';

  String get dimensionLabel => width > 0 && height > 0 ? '$width × $height' : '—';

  /// 原生侧返回的扁平数组：[id, created, modified, w, h, duration,
  /// kind, live, fav, hidden, filename, bytes, known, source]
  factory PhotoItem.fromRow(List<dynamic> row) {
    int intAt(int index) => (row.length > index ? row[index] as num? : null)?.toInt() ?? 0;
    double doubleAt(int index) =>
        (row.length > index ? row[index] as num? : null)?.toDouble() ?? 0;
    String stringAt(int index) =>
        row.length > index ? (row[index] as String? ?? '') : '';

    return PhotoItem(
      id: stringAt(0),
      created: doubleAt(1),
      modified: doubleAt(2),
      width: intAt(3),
      height: intAt(4),
      duration: doubleAt(5),
      kind: MediaKind.fromCode(intAt(6)),
      isLive: intAt(7) == 1,
      isFavorite: intAt(8) == 1,
      isHidden: intAt(9) == 1,
      filename: stringAt(10),
      bytes: intAt(11),
      bytesKnown: intAt(12) == 1,
      sizeSource: stringAt(13),
    );
  }

  PhotoItem copyWith({
    int? bytes,
    bool? bytesKnown,
    String? filename,
    String? sizeSource,
    bool? isFavorite,
    bool? isHidden,
  }) {
    return PhotoItem(
      id: id,
      created: created,
      modified: modified,
      width: width,
      height: height,
      duration: duration,
      kind: kind,
      isLive: isLive,
      isFavorite: isFavorite ?? this.isFavorite,
      isHidden: isHidden ?? this.isHidden,
      filename: filename ?? this.filename,
      bytes: bytes ?? this.bytes,
      bytesKnown: bytesKnown ?? this.bytesKnown,
      sizeSource: sizeSource ?? this.sizeSource,
    );
  }
}

/// 大小区间。按大小排序时用它做分组标题 —— 相当于系统相册的「年/月/日」，
/// 只是分组维度换成了文件大小。
class SizeBucket {
  const SizeBucket(this.id, this.label, this.min, this.max);

  final String id;
  final String label;

  /// 下界（含）
  final int min;

  /// 上界（不含），null 表示无穷
  final int? max;

  bool contains(int bytes) {
    if (bytes < min) return false;
    if (max == null) return true;
    return bytes < max!;
  }

  static const int kb = 1024;
  static const int mb = 1024 * 1024;

  static const SizeBucket over100mb = SizeBucket('b100', '100 MB 以上', 100 * mb, null);
  static const SizeBucket from50to100 =
      SizeBucket('b50', '50 – 100 MB', 50 * mb, 100 * mb);
  static const SizeBucket from20to50 = SizeBucket('b20', '20 – 50 MB', 20 * mb, 50 * mb);
  static const SizeBucket from10to20 = SizeBucket('b10', '10 – 20 MB', 10 * mb, 20 * mb);
  static const SizeBucket from5to10 = SizeBucket('b5', '5 – 10 MB', 5 * mb, 10 * mb);
  static const SizeBucket from1to5 = SizeBucket('b1', '1 – 5 MB', 1 * mb, 5 * mb);
  static const SizeBucket from100kb = SizeBucket('b100k', '100 KB – 1 MB', 100 * kb, 1 * mb);
  static const SizeBucket under100kb = SizeBucket('b0', '小于 100 KB', 1, 100 * kb);
  static const SizeBucket unknown = SizeBucket('unknown', '大小未知', 0, null);

  /// 从大到小，界面默认顺序
  static const List<SizeBucket> all = <SizeBucket>[
    over100mb,
    from50to100,
    from20to50,
    from10to20,
    from5to10,
    from1to5,
    from100kb,
    under100kb,
  ];

  static SizeBucket forBytes(int bytes) {
    if (bytes <= 0) return unknown;
    for (final bucket in all) {
      if (bucket.contains(bytes)) return bucket;
    }
    return unknown;
  }
}
