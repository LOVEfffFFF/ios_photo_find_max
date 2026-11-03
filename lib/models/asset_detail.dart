import '../util/format.dart';
import 'photo_item.dart';

/// 详情页拿到的一整份资产信息（原生 `assetDetail` 返回）。
class AssetDetail {
  const AssetDetail({
    required this.id,
    required this.filename,
    required this.uti,
    required this.kind,
    required this.playbackStyle,
    required this.subtypes,
    required this.width,
    required this.height,
    required this.duration,
    required this.created,
    required this.modified,
    required this.favorite,
    required this.hidden,
    required this.hasAdjustments,
    required this.sourceName,
    required this.burstIdentifier,
    required this.hasLocation,
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.albums,
    required this.resources,
    required this.bytes,
    required this.sizeSource,
    required this.error,
  });

  final String id;
  final String filename;
  final String uti;
  final MediaKind kind;
  final int playbackStyle;
  final List<String> subtypes;
  final int width;
  final int height;
  final double duration;
  final double created;
  final double modified;
  final bool favorite;
  final bool hidden;
  final bool hasAdjustments;
  final String sourceName;
  final String burstIdentifier;
  final bool hasLocation;
  final double latitude;
  final double longitude;
  final String placeName;
  final List<String> albums;
  final List<AssetResourceDetail> resources;

  /// 所有资源合计
  final int bytes;

  /// "meta" / "read" / "partial" / ""
  final String sizeSource;

  /// 非空表示原生侧没能读到这个资产（通常是被删了）
  final String error;

  bool get failed => error.isNotEmpty;

  String get typeLabel {
    if (subtypes.isNotEmpty) {
      final base = playbackStyleLabel;
      return subtypes.contains(base) ? subtypes.join('、') : '$base · ${subtypes.join('、')}';
    }
    return playbackStyleLabel;
  }

  String get playbackStyleLabel {
    if (kind == MediaKind.video) return '视频';
    switch (playbackStyle) {
      case 2:
        return '动图';
      case 3:
        return '实况照片';
      case 4:
        return '视频';
      case 5:
        return '循环视频';
      default:
        return hasAdjustments ? '照片（已编辑）' : '照片';
    }
  }

  String get dimensionLabel => width > 0 && height > 0 ? '$width × $height' : '—';

  String get megapixelLabel {
    if (width <= 0 || height <= 0) return '';
    final mp = width * height / 1000000.0;
    return '${mp.toStringAsFixed(1)} MP';
  }

  String get sizeLabel => formatBytes(bytes);

  String get durationLabel => duration > 0 ? formatDuration(duration) : '—';

  String get placeLabel {
    if (!hasLocation) return '无位置信息';
    if (placeName.isNotEmpty) return placeName;
    return formatCoordinates(latitude, longitude);
  }

  factory AssetDetail.fromChannel(Map<String, dynamic> map) {
    List<String> strings(Object? value) {
      if (value is! List) return const <String>[];
      return value.map((e) => '$e').toList();
    }

    List<AssetResourceDetail> rows(Object? value) {
      if (value is! List) return const <AssetResourceDetail>[];
      return value
          .whereType<Map>()
          .map((e) => AssetResourceDetail.fromChannel(Map<String, dynamic>.from(e)))
          .toList();
    }

    return AssetDetail(
      id: '${map['id'] ?? ''}',
      filename: '${map['filename'] ?? ''}',
      uti: '${map['uti'] ?? ''}',
      kind: MediaKind.fromCode((map['kind'] as num?)?.toInt() ?? 0),
      playbackStyle: (map['playbackStyle'] as num?)?.toInt() ?? 0,
      subtypes: strings(map['subtypes']),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toDouble() ?? 0,
      created: (map['created'] as num?)?.toDouble() ?? 0,
      modified: (map['modified'] as num?)?.toDouble() ?? 0,
      favorite: map['favorite'] == true,
      hidden: map['hidden'] == true,
      hasAdjustments: map['hasAdjustments'] == true,
      sourceName: '${map['sourceName'] ?? ''}',
      burstIdentifier: '${map['burstIdentifier'] ?? ''}',
      hasLocation: map['hasLocation'] == true,
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      placeName: '${map['placeName'] ?? ''}',
      albums: strings(map['albums']),
      resources: rows(map['resources']),
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      sizeSource: '${map['sizeSource'] ?? ''}',
      error: '${map['error'] ?? ''}',
    );
  }
}

/// 一个资产下挂在相册里的一份资源文件。
///
/// 一张照片可能不止一份文件：Live Photo 有配对视频，ProRAW 有 DNG + 渲染图 +
/// 编辑指令。详情页把它们逐条列出来，方便判断「到底是哪个文件占地方」。
class AssetResourceDetail {
  const AssetResourceDetail({
    required this.index,
    required this.type,
    required this.typeName,
    required this.uti,
    required this.filename,
    required this.bytes,
  });

  final int index;
  final int type;
  final String typeName;
  final String uti;
  final String filename;
  final int bytes;

  String get label {
    switch (typeName) {
      case 'photo':
        return '原始照片';
      case 'video':
        return '原始视频';
      case 'audio':
        return '音频';
      case 'alternatePhoto':
        return '替代照片';
      case 'fullSizePhoto':
        return '全尺寸照片';
      case 'fullSizeVideo':
        return '全尺寸视频';
      case 'adjustmentData':
        return '编辑数据';
      case 'adjustmentBasePhoto':
        return '编辑前照片';
      case 'pairedVideo':
        return '实况配对视频';
      case 'fullSizePairedVideo':
        return '全尺寸配对视频';
      case 'adjustmentBasePairedVideo':
        return '编辑前配对视频';
      default:
        return typeName;
    }
  }

  String get sizeLabel => bytes > 0 ? formatBytes(bytes) : '未知';

  factory AssetResourceDetail.fromChannel(Map<String, dynamic> map) {
    return AssetResourceDetail(
      index: (map['index'] as num?)?.toInt() ?? 0,
      type: (map['type'] as num?)?.toInt() ?? 0,
      typeName: '${map['typeName'] ?? ''}',
      uti: '${map['uti'] ?? ''}',
      filename: '${map['filename'] ?? ''}',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
    );
  }
}
