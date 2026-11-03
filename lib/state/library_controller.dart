import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/photo_item.dart';
import '../services/photo_library_api.dart';
import '../services/thumbnail_loader.dart';

enum SortMode { sizeDesc, sizeAsc, dateDesc }

extension SortModeX on SortMode {
  String get label {
    switch (this) {
      case SortMode.sizeDesc:
        return '大小：从大到小';
      case SortMode.sizeAsc:
        return '大小：从小到大';
      case SortMode.dateDesc:
        return '日期：最新优先';
    }
  }

  String get shortLabel {
    switch (this) {
      case SortMode.sizeDesc:
        return '大到小';
      case SortMode.sizeAsc:
        return '小到大';
      case SortMode.dateDesc:
        return '按日期';
    }
  }

  bool get isSize => this != SortMode.dateDesc;
}

enum KindFilter { all, photos, videos }

extension KindFilterX on KindFilter {
  String get label {
    switch (this) {
      case KindFilter.all:
        return '全部';
      case KindFilter.photos:
        return '照片';
      case KindFilter.videos:
        return '视频';
    }
  }
}

/// 一个分组标题 + 属于它的项目。
class PhotoSection {
  const PhotoSection({required this.title, required this.items, this.subtitle = ''});

  final String title;
  final String subtitle;
  final List<PhotoItem> items;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.bytes);
}

/// 整个 App 的状态。故意不引状态管理库：一个页面一个 controller，
/// 用 ChangeNotifier + ListenableBuilder 足够，也少一个 CI 变数。
class LibraryController extends ChangeNotifier {
  LibraryController({PhotoLibraryApi api = const PhotoLibraryApi()}) : _api = api;

  final PhotoLibraryApi _api;

  String status = 'unknown';
  bool initializing = true;
  bool scanning = false;
  int scanDone = 0;
  int scanTotal = 0;
  String sizeSource = '';
  String? message;

  SortMode sortMode = SortMode.sizeDesc;
  KindFilter kindFilter = KindFilter.all;
  SizeBucket? bucketFilter;
  bool includeHidden = false;

  bool selecting = false;
  final Set<String> selected = <String>{};

  final Map<String, PhotoItem> _byId = <String, PhotoItem>{};
  List<PhotoItem> _items = <PhotoItem>[];
  List<PhotoItem> _visible = <PhotoItem>[];

  /// 已经确认大小的项目合计
  int totalBytes = 0;
  int knownCount = 0;

  StreamSubscription<Map<String, dynamic>>? _progressSub;
  Timer? _rebuildTimer;
  bool _disposed = false;

  List<PhotoItem> get visible => _visible;
  List<PhotoItem> get allItems => _items;
  int get count => _visible.length;
  int get totalCount => _items.length;
  int get missingCount => _items.length - knownCount;

  bool get hasAccess => status == 'authorized' || status == 'limited';
  bool get isLimited => status == 'limited';

  int get visibleBytes => _visible.fold<int>(0, (sum, item) => sum + item.bytes);

  PhotoItem? get largest =>
      _visible.isEmpty ? null : (_visible.first.bytes > 0 ? _visible.first : null);

  Future<void> init() async {
    _progressSub ??= PhotoLibraryApi.progress.listen(_onProgress);
    status = await _api.authorizationStatus();
    if (hasAccess) {
      await refresh();
    } else {
      initializing = false;
      _notify();
    }
  }

  Future<void> requestPermission() async {
    initializing = true;
    _notify();
    status = await _api.requestAuthorization();
    if (hasAccess) {
      await refresh();
    } else {
      initializing = false;
      _notify();
    }
  }

  /// 重新读一遍相册列表。已缓存的大小直接带出来，随后再增量扫描缺的。
  ///
  /// [silent] 用于从后台回到前台时静默同步 —— 不显示加载态，避免界面闪一下。
  Future<void> refresh({bool forceRescan = false, bool silent = false}) async {
    if (!hasAccess) return;
    // 正在扫描时不要去打断它：扫描结束会自己刷新结果
    if (scanning && silent) return;
    initializing = !silent;
    _notify();

    final snapshot = await _api.loadAssets(includeHidden: includeHidden);
    status = snapshot.status;
    _items = snapshot.items;
    _byId
      ..clear()
      ..addEntries(_items.map((item) => MapEntry(item.id, item)));
    totalBytes = snapshot.totalBytes;
    knownCount = snapshot.knownCount;
    sizeSource = snapshot.sizeSource;
    selected.clear();
    selecting = false;
    initializing = false;
    _rebuild();
    _notify();

    if (_items.isEmpty) return;
    unawaited(startScan(force: forceRescan));
  }

  Future<void> startScan({bool force = false}) async {
    if (scanning || !hasAccess) return;
    scanning = true;
    scanDone = 0;
    scanTotal = _items.length;
    _notify();
    final result = await _api.computeSizes(force: force);
    scanning = false;
    if (result.error != null) message = result.error;
    if (result.sizeSource.isNotEmpty) sizeSource = result.sizeSource;
    if (result.totalBytes > 0) totalBytes = result.totalBytes;
    _rebuild();
    _notify();
  }

  void _onProgress(Map<String, dynamic> event) {
    final type = event['type'];
    if (type == 'libraryChanged') {
      // 相册变了（别处删除 / 改了「部分访问」的选图）：静默同步一次
      if (!scanning) unawaited(refresh(silent: true));
      return;
    }
    if (type == 'start') {
      scanTotal = (event['total'] as num?)?.toInt() ?? 0;
      scanning = true;
      _notify();
      return;
    }
    if (type == 'batch') {
      final items = event['items'];
      if (items is List) {
        for (final row in items) {
          if (row is! List || row.length < 2) continue;
          final id = '${row[0]}';
          final bytes = (row[1] as num?)?.toInt() ?? 0;
          final filename = row.length > 2 ? '${row[2]}' : '';
          final source = row.length > 3 ? '${row[3]}' : '';
          final existing = _byId[id];
          if (existing == null) continue;
          final updated = existing.copyWith(
            bytes: bytes,
            bytesKnown: bytes > 0,
            filename: filename.isEmpty ? existing.filename : filename,
            sizeSource: source,
          );
          _byId[id] = updated;
          // 只有「之前不知道」的才计数，否则缓存的那些会被重复累加
          if (bytes > 0 && !existing.bytesKnown) knownCount++;
        }
      }
      scanDone = (event['done'] as num?)?.toInt() ?? scanDone;
      scanTotal = (event['total'] as num?)?.toInt() ?? scanTotal;
      final total = (event['totalBytes'] as num?)?.toInt();
      if (total != null) totalBytes = total;
      _items = _byId.values.toList(growable: false);
      _scheduleRebuild();
      return;
    }
    if (type == 'done') {
      scanning = false;
      scanDone = (event['done'] as num?)?.toInt() ?? scanDone;
      scanTotal = (event['total'] as num?)?.toInt() ?? scanTotal;
      final total = (event['totalBytes'] as num?)?.toInt();
      if (total != null) totalBytes = total;
      final source = '${event['sizeSource'] ?? ''}';
      if (source.isNotEmpty) sizeSource = source;
      _items = _byId.values.toList(growable: false);
      _rebuild();
      _notify();
    }
  }

  void _scheduleRebuild() {
    _rebuildTimer?.cancel();
    _rebuildTimer = Timer(const Duration(milliseconds: 250), () {
      _rebuild();
      _notify();
    });
  }

  void setSortMode(SortMode mode) {
    if (sortMode == mode) return;
    sortMode = mode;
    _rebuild();
    _notify();
  }

  void setKindFilter(KindFilter filter) {
    if (kindFilter == filter) return;
    kindFilter = filter;
    _rebuild();
    _notify();
  }

  void setBucketFilter(SizeBucket? bucket) {
    bucketFilter = bucket;
    _rebuild();
    _notify();
  }

  void setIncludeHidden(bool value) {
    if (includeHidden == value) return;
    includeHidden = value;
    unawaited(refresh());
  }

  void toggleSelect(String id) {
    if (selected.contains(id)) {
      selected.remove(id);
    } else {
      selected.add(id);
    }
    selecting = selected.isNotEmpty;
    _notify();
  }

  void startSelection(String id) {
    selecting = true;
    selected.add(id);
    _notify();
  }

  void clearSelection() {
    selecting = false;
    selected.clear();
    _notify();
  }

  void selectAllVisible() {
    selected.addAll(_visible.map((item) => item.id));
    selecting = selected.isNotEmpty;
    _notify();
  }

  void selectOnly(String id) {
    selecting = true;
    selected
      ..clear()
      ..add(id);
    _notify();
  }

  /// 删除。系统会把它们移进「最近删除」，30 天后自动清理。
  Future<DeleteResult> deleteIds(List<String> ids) async {
    if (ids.isEmpty) {
      return const DeleteResult(deleted: 0, failed: 0, error: '没有选中任何项目');
    }
    final result = await _api.deleteAssets(ids);
    if (result.deleted > 0) {
      final removed = List<String>.from(ids);
      for (final id in removed) {
        final item = _byId.remove(id);
        if (item != null && item.bytesKnown) {
          knownCount = knownCount > 0 ? knownCount - 1 : 0;
          totalBytes = totalBytes > item.bytes ? totalBytes - item.bytes : 0;
        }
        selected.remove(id);
      }
      _items = _byId.values.toList(growable: false);
      selecting = selected.isNotEmpty;
      _rebuild();
      _notify();
    }
    return result;
  }

  Future<bool> setFavorite(String id, bool value) async {
    final ok = await _api.setFavorite(id, value);
    if (ok) {
      final item = _byId[id];
      if (item != null) {
        _byId[id] = item.copyWith(isFavorite: value);
        _items = _byId.values.toList(growable: false);
        _rebuild();
        _notify();
      }
    }
    return ok;
  }

  Future<bool> setHidden(String id, bool value) async {
    final ok = await _api.setHidden(id, value);
    if (ok) {
      final item = _byId[id];
      if (item != null) {
        _byId[id] = item.copyWith(isHidden: value);
        _items = _byId.values.toList(growable: false);
        _rebuild();
        _notify();
      }
    }
    return ok;
  }

  void clearMessage() {
    message = null;
  }

  /// 供统计页使用：每个大小区间的数量与占用
  Map<String, ({int count, int bytes})> buildBucketStats() {
    final result = <String, ({int count, int bytes})>{};
    for (final bucket in SizeBucket.all) {
      result[bucket.id] = (count: 0, bytes: 0);
    }
    result[SizeBucket.unknown.id] = (count: 0, bytes: 0);
    for (final item in _items) {
      if (!_matchesKind(item)) continue;
      final bucket = item.bytesKnown ? SizeBucket.forBytes(item.bytes) : SizeBucket.unknown;
      final current = result[bucket.id] ?? (count: 0, bytes: 0);
      result[bucket.id] = (count: current.count + 1, bytes: current.bytes + item.bytes);
    }
    return result;
  }

  List<PhotoItem> topLargest(int limit) {
    final list = _items.where(_matchesKind).where((item) => item.bytes > 0).toList()
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return list.take(limit).toList();
  }

  /// 图库页要显示的扁平列表：按大小排序时切成区间分组，
  /// 相当于系统相册的「年 / 月」，只是分组维度换成了文件大小。
  List<PhotoSection> buildSections() {
    if (!sortMode.isSize) {
      if (_visible.isEmpty) return const <PhotoSection>[];
      return <PhotoSection>[
        PhotoSection(title: '按日期', items: _visible),
      ];
    }

    if (bucketFilter != null) {
      if (_visible.isEmpty) return const <PhotoSection>[];
      return <PhotoSection>[
        PhotoSection(
          title: bucketFilter!.label,
          subtitle: '${_visible.length} 项 · ${_formatBytes(visibleBytes)}',
          items: _visible,
        ),
      ];
    }

    final grouped = <String, List<PhotoItem>>{};
    for (final item in _visible) {
      final bucket = item.bytesKnown ? SizeBucket.forBytes(item.bytes) : SizeBucket.unknown;
      grouped.putIfAbsent(bucket.id, () => <PhotoItem>[]).add(item);
    }

    final sections = <PhotoSection>[];
    for (final bucket in <SizeBucket>[...SizeBucket.all, SizeBucket.unknown]) {
      final items = grouped[bucket.id];
      if (items == null || items.isEmpty) continue;
      final bytes = items.fold<int>(0, (sum, item) => sum + item.bytes);
      sections.add(PhotoSection(
        title: bucket.label,
        subtitle: '${items.length} 项 · ${_formatBytes(bytes)}',
        items: items,
      ));
    }
    return sections;
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '$bytes B';
    final digits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  bool _matchesKind(PhotoItem item) {
    switch (kindFilter) {
      case KindFilter.all:
        return true;
      case KindFilter.photos:
        return item.kind == MediaKind.photo;
      case KindFilter.videos:
        return item.kind == MediaKind.video;
    }
  }

  void _rebuild() {
    final list = <PhotoItem>[];
    for (final item in _items) {
      if (!_matchesKind(item)) continue;
      if (bucketFilter != null) {
        final bucket = item.bytesKnown ? SizeBucket.forBytes(item.bytes) : SizeBucket.unknown;
        if (bucket.id != bucketFilter!.id) continue;
      }
      list.add(item);
    }
    list.sort(_compare);
    _visible = list;
  }

  int _compare(PhotoItem a, PhotoItem b) {
    if (sortMode == SortMode.dateDesc) {
      return b.created.compareTo(a.created);
    }
    final aUnknown = !a.bytesKnown || a.bytes <= 0;
    final bUnknown = !b.bytesKnown || b.bytes <= 0;
    if (aUnknown && bUnknown) return b.created.compareTo(a.created);
    if (aUnknown) return 1; // 大小未知永远沉底，无论升序降序
    if (bUnknown) return -1;
    if (a.bytes == b.bytes) return b.created.compareTo(a.created);
    return sortMode == SortMode.sizeDesc
        ? b.bytes.compareTo(a.bytes)
        : a.bytes.compareTo(b.bytes);
  }

  void clearImageCaches() {
    ThumbnailLoader.instance.clear();
    PreviewLoader.instance.clear();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rebuildTimer?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }
}
