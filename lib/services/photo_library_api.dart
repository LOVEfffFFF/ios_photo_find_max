import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/asset_detail.dart';
import '../models/photo_item.dart';

/// 一次相册列表读取的结果。
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.status,
    required this.items,
    required this.totalBytes,
    required this.knownCount,
    required this.sizeSource,
  });

  final String status;
  final List<PhotoItem> items;

  /// 已知大小的项目合计字节
  final int totalBytes;
  final int knownCount;
  final String sizeSource;

  int get missingCount => items.length - knownCount;
}

class ScanResult {
  const ScanResult({
    required this.scanned,
    required this.total,
    required this.totalBytes,
    required this.sizeSource,
    this.error,
  });

  final int scanned;
  final int total;
  final int totalBytes;
  final String sizeSource;
  final String? error;
}

class DeleteResult {
  const DeleteResult({
    required this.deleted,
    required this.failed,
    this.error,
  });

  final int deleted;
  final int failed;
  final String? error;

  bool get ok => deleted > 0 && (error == null || error!.isEmpty);
}

/// 原生 PhotoKit 桥。
///
/// 全部方法都对 `MissingPluginException` 做了兜底：这个 App 只在 iOS 上有原生实现，
/// 在别的平台上跑起来应该「看不到照片」而不是「一进页面就崩」。
class PhotoLibraryApi {
  const PhotoLibraryApi();

  static const MethodChannel _channel = MethodChannel('com.photosize/photolib');
  static const EventChannel _events = EventChannel('com.photosize/progress');

  /// 扫描进度事件：
  ///   {type: start, total}
  ///   {type: batch, items: [[id, bytes, filename, source], ...], done, total, totalBytes}
  ///   {type: done, done, total, totalBytes, sizeSource}
  static Stream<Map<String, dynamic>> get progress {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return event.map((key, value) => MapEntry('$key', value));
      }
      return <String, dynamic>{};
    }).handleError((Object _) {
      // 原生侧没装通道时（非 iOS），静默忽略，界面沿用「大小未知」
    });
  }

  Future<String> authorizationStatus() async {
    try {
      final raw = await _channel.invokeMethod('authorizationStatus');
      if (raw is Map) return '${raw['status'] ?? 'unknown'}';
    } on MissingPluginException {
      return 'unsupported';
    } catch (_) {
      return 'unknown';
    }
    return 'unknown';
  }

  Future<String> requestAuthorization() async {
    try {
      final raw = await _channel.invokeMethod('requestAuthorization');
      if (raw is Map) return '${raw['status'] ?? 'unknown'}';
    } on MissingPluginException {
      return 'unsupported';
    } catch (_) {
      return 'unknown';
    }
    return 'unknown';
  }

  Future<LibrarySnapshot> loadAssets({bool includeHidden = false}) async {
    try {
      final raw = await _channel.invokeMethod('loadAssets', {
        'includeHidden': includeHidden,
      });
      if (raw is Map) {
        final rows = (raw['rows'] as List?) ?? const [];
        final items = <PhotoItem>[];
        for (final row in rows) {
          if (row is List) {
            final item = PhotoItem.fromRow(row);
            if (item.id.isNotEmpty) items.add(item);
          }
        }
        return LibrarySnapshot(
          status: '${raw['status'] ?? 'unknown'}',
          items: items,
          totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
          knownCount: (raw['knownCount'] as num?)?.toInt() ?? 0,
          sizeSource: '${raw['sizeSource'] ?? ''}',
        );
      }
    } on MissingPluginException {
      return const LibrarySnapshot(
        status: 'unsupported',
        items: <PhotoItem>[],
        totalBytes: 0,
        knownCount: 0,
        sizeSource: '',
      );
    } catch (error) {
      return LibrarySnapshot(
        status: 'error',
        items: const <PhotoItem>[],
        totalBytes: 0,
        knownCount: 0,
        sizeSource: '',
      );
    }
    return const LibrarySnapshot(
      status: 'unknown',
      items: <PhotoItem>[],
      totalBytes: 0,
      knownCount: 0,
      sizeSource: '',
    );
  }

  Future<ScanResult> computeSizes({
    bool force = false,
    bool allowNetwork = false,
  }) async {
    try {
      final raw = await _channel.invokeMethod('computeSizes', {
        'force': force,
        'allowNetwork': allowNetwork,
      });
      if (raw is Map) {
        final error = raw['error'];
        return ScanResult(
          scanned: (raw['scanned'] as num?)?.toInt() ?? 0,
          total: (raw['total'] as num?)?.toInt() ?? 0,
          totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
          sizeSource: '${raw['sizeSource'] ?? ''}',
          error: error is String && error.isNotEmpty ? error : null,
        );
      }
    } on MissingPluginException {
      return const ScanResult(
        scanned: 0,
        total: 0,
        totalBytes: 0,
        sizeSource: '',
        error: '当前平台不支持相册访问',
      );
    } catch (error) {
      return ScanResult(
        scanned: 0,
        total: 0,
        totalBytes: 0,
        sizeSource: '',
        error: '$error',
      );
    }
    return const ScanResult(scanned: 0, total: 0, totalBytes: 0, sizeSource: '');
  }

  /// 网格缩略图。返回 JPEG 字节，失败返回 null。
  Future<Uint8List?> thumbnail(String id, {int px = 320}) async {
    return _image('thumbnail', id, px: px, quality: 0.82);
  }

  /// 大图预览（详情页）。视频返回的是封面帧。
  Future<Uint8List?> preview(String id, {int px = 1600}) async {
    return _image('preview', id, px: px, quality: 0.9);
  }

  Future<Uint8List?> _image(
    String method,
    String id, {
    required int px,
    required double quality,
  }) async {
    if (id.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod(method, {
        'id': id,
        'px': px,
        'quality': quality,
      });
      if (raw is Uint8List) return raw;
      if (raw is ByteData) return raw.buffer.asUint8List();
    } on MissingPluginException {
      return null;
    } catch (_) {
      // 单张图取不到不该影响整页
    }
    return null;
  }

  Future<AssetDetail?> assetDetail(String id) async {
    if (id.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod('assetDetail', {'id': id});
      if (raw is Map) {
        final detail = AssetDetail.fromChannel(Map<String, dynamic>.from(raw));
        if (detail.failed) return null;
        return detail;
      }
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// 删除 —— 系统行为：进「最近删除」，30 天后才真正消失。
  ///
  /// `confirm` 在 Dart 侧硬编码为 true（原生侧也强制校验），
  /// 避免任何调用方「忘记传」导致误删。
  Future<DeleteResult> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) {
      return const DeleteResult(deleted: 0, failed: 0, error: '没有选中任何项目');
    }
    try {
      final raw = await _channel.invokeMethod('deleteAssets', {
        'ids': ids,
        'confirm': true,
      });
      if (raw is Map) {
        final error = '${raw['error'] ?? ''}';
        return DeleteResult(
          deleted: (raw['deleted'] as num?)?.toInt() ?? 0,
          failed: (raw['failed'] as num?)?.toInt() ?? 0,
          error: error.isEmpty ? null : error,
        );
      }
    } on MissingPluginException {
      return const DeleteResult(deleted: 0, failed: 0, error: '当前平台不支持删除');
    } catch (error) {
      return DeleteResult(deleted: 0, failed: ids.length, error: '$error');
    }
    return const DeleteResult(deleted: 0, failed: 0, error: '原生返回格式异常');
  }

  Future<bool> setFavorite(String id, bool value) =>
      _setFlag('setFavorite', id, value);

  Future<bool> setHidden(String id, bool value) =>
      _setFlag('setHidden', id, value);

  Future<bool> _setFlag(String method, String id, bool value) async {
    try {
      final raw = await _channel.invokeMethod(method, {'id': id, 'value': value});
      if (raw is Map) return raw['ok'] == true;
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {
      // 打不开系统设置就算了，界面上还有文字说明
    }
  }

  Future<bool> presentLimitedPicker() async {
    try {
      final raw = await _channel.invokeMethod('presentLimitedPicker');
      return raw == true;
    } catch (_) {
      return false;
    }
  }
}
