import 'dart:async';
import 'dart:typed_data';

import 'photo_library_api.dart';

/// 缩略图加载器。
///
/// 三个作用，缺一个滚动就会卡：
///   1. 内存 LRU —— 来回滚动不重复走通道（一次通道往返 ≈ 一张图的解码时间）；
///   2. 同 key 合流 —— 同一张图被两处同时请求只发一次；
///   3. 并发限流 —— 系统 PhotoKit 的图片请求队列是有限的，一次丢几百个进去
///      反而会让「当前屏幕」的图排在最后。
class ThumbnailLoader {
  ThumbnailLoader._();

  static final ThumbnailLoader instance = ThumbnailLoader._();

  static const int _maxEntries = 500;
  static const int _maxConcurrent = 8;

  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};
  final List<Completer<void>> _waiters = <Completer<void>>[];

  int _active = 0;

  Future<Uint8List?> load(String id, int px) {
    final key = '$id@$px';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // 重新插到队尾，保持 LRU 顺序
      return Future<Uint8List?>.value(cached);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _fetch(key, id, px);
    _inflight[key] = future;
    return future;
  }

  Future<Uint8List?> _fetch(String key, String id, int px) async {
    await _acquire();
    try {
      final bytes = await PhotoLibraryApi.thumbnail(id, px: px);
      if (bytes != null && bytes.isNotEmpty) {
        _cache[key] = bytes;
        while (_cache.length > _maxEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return bytes;
    } finally {
      _release();
      _inflight.remove(key);
    }
  }

  Future<void> _acquire() {
    if (_active < _maxConcurrent) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      // 名额直接转交，_active 不变
      next.complete();
      return;
    }
    _active = (_active - 1).clamp(0, _maxConcurrent);
  }

  void clear() {
    _cache.clear();
  }
}

/// 详情页大图加载器。尺寸大得多，只留很少几张，避免吃光内存。
class PreviewLoader {
  PreviewLoader._();

  static final PreviewLoader instance = PreviewLoader._();

  static const int _maxEntries = 6;

  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inflight = <String, Future<Uint8List?>>{};

  Future<Uint8List?> load(String id, {int px = 1600}) {
    final key = '$id@$px';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future<Uint8List?>.value(cached);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = PhotoLibraryApi.preview(id, px: px).then((bytes) {
      if (bytes != null && bytes.isNotEmpty) {
        _cache[key] = bytes;
        while (_cache.length > _maxEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return bytes;
    }).whenComplete(() {
      _inflight.remove(key);
    });

    _inflight[key] = future;
    return future;
  }

  void clear() {
    _cache.clear();
  }
}
