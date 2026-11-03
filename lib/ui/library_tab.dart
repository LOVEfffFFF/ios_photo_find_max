import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/photo_item.dart';
import '../services/photo_library_api.dart';
import '../state/library_controller.dart';
import '../util/format.dart';
import 'dialogs.dart';
import 'photo_detail_page.dart';
import 'theme.dart';
import 'widgets/photo_tile.dart';

/// 图库页：按大小分组的方形网格。
///
/// 结构刻意照抄系统「照片」App：
///   · 大标题 + 固定筛选条
///   · 分组标题吸顶（系统是「年 / 月」，这里是大小区间）
///   · 三列方图、2px 间距、无圆角
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final sections = controller.buildSections();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // 一格的物理像素，直接按它取图，避免「拿 400px 的图缩到 120px 显示」
    final thumbPx = ((screenWidth / 3) * ratio).round().clamp(160, 900);

    return RefreshIndicator(
      onRefresh: () => controller.refresh(),
      color: AppTheme.blue,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (controller.selecting)
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              scrolledUnderElevation: 0.5,
              leadingWidth: 68,
              leading: TextButton(
                onPressed: controller.clearSelection,
                child: const Text('取消', style: TextStyle(fontSize: 16)),
              ),
              title: Text(
                '已选择 ${controller.selected.length} 项',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              actions: [
                TextButton(
                  onPressed: controller.selectAllVisible,
                  child: const Text('全选', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 6),
              ],
            )
          else
            SliverAppBar.large(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              scrolledUnderElevation: 0.5,
              title: const Text('图库'),
              actions: [
                IconButton(
                  tooltip: '排序',
                  icon: const Icon(Icons.swap_vert, size: 22),
                  onPressed: () => _showSortMenu(context),
                ),
                IconButton(
                  tooltip: '更多',
                  icon: const Icon(Icons.more_horiz, size: 22),
                  onPressed: () => _showMoreMenu(context),
                ),
                const SizedBox(width: 4),
              ],
            ),

          if (!controller.selecting)
            SliverToBoxAdapter(child: _FilterBar(controller: controller)),

          if (controller.isLimited)
            SliverToBoxAdapter(
              child: _LimitedBanner(
                onManage: () async {
                  final opened = await const PhotoLibraryApi().presentLimitedPicker();
                  if (!opened) return;
                },
              ),
            ),

          SliverToBoxAdapter(child: _SummaryCard(controller: controller)),

          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyView(controller: controller),
            )
          else ...[
            for (final section in sections) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _SectionHeaderDelegate(
                  title: section.title,
                  trailing: section.subtitle,
                ),
              ),
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: section.items.length,
                  (context, index) {
                    final item = section.items[index];
                    return PhotoTile(
                      key: ValueKey<String>(item.id),
                      item: item,
                      thumbPx: thumbPx,
                      selecting: controller.selecting,
                      selected: controller.selected.contains(item.id),
                      onTap: () => _onTap(context, item),
                      onLongPress: () {
                        if (controller.selecting) return;
                        HapticFeedback.mediumImpact();
                        controller.startSelection(item.id);
                      },
                    );
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ],
      ),
    );
  }

  void _onTap(BuildContext context, PhotoItem item) {
    if (controller.selecting) {
      controller.toggleSelect(item.id);
      return;
    }
    final index = controller.visible.indexWhere((e) => e.id == item.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoDetailPage(
          controller: controller,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  Future<void> _showSortMenu(BuildContext context) async {
    final mode = await showActionSheet<SortMode>(
      context,
      title: '排序方式',
      items: [
        for (final mode in SortMode.values)
          ActionSheetItem<SortMode>(
            label: mode == controller.sortMode ? '${mode.label} ✓' : mode.label,
            value: mode,
          ),
      ],
    );
    if (mode != null) controller.setSortMode(mode);
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final action = await showActionSheet<String>(
      context,
      title: '更多操作',
      items: [
        const ActionSheetItem<String>(label: '重新扫描文件大小', value: 'rescan'),
        ActionSheetItem<String>(
          label: controller.includeHidden ? '不显示已隐藏项目' : '显示已隐藏项目',
          value: 'hidden',
        ),
        const ActionSheetItem<String>(label: '刷新相册', value: 'refresh'),
      ],
    );
    switch (action) {
      case 'rescan':
        controller.clearImageCaches();
        await controller.refresh(forceRescan: true);
        break;
      case 'hidden':
        controller.setIncludeHidden(!controller.includeHidden);
        break;
      case 'refresh':
        await controller.refresh();
        break;
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (final filter in KindFilter.values) ...[
            _Chip(
              label: filter.label,
              selected: controller.kindFilter == filter,
              onTap: () => controller.setKindFilter(filter),
            ),
            const SizedBox(width: 8),
          ],
          Container(width: 1, height: 18, color: AppTheme.separator, margin: const EdgeInsets.symmetric(horizontal: 4)),
          const SizedBox(width: 4),
          _Chip(
            label: controller.sortMode.shortLabel,
            selected: controller.sortMode != SortMode.dateDesc,
            icon: Icons.swap_vert,
            onTap: () async {
              final mode = await showActionSheet<SortMode>(
                context,
                title: '排序方式',
                items: [
                  for (final mode in SortMode.values)
                    ActionSheetItem<SortMode>(
                      label: mode == controller.sortMode ? '${mode.label} ✓' : mode.label,
                      value: mode,
                    ),
                ],
              );
              if (mode != null) controller.setSortMode(mode);
            },
          ),
          if (controller.bucketFilter != null) ...[
            const SizedBox(width: 8),
            _Chip(
              label: controller.bucketFilter!.label,
              selected: true,
              icon: Icons.close,
              onTap: () => controller.setBucketFilter(null),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.blue.withValues(alpha: 0.12) : AppTheme.groupedBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppTheme.blue : Colors.black87,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 3),
              Icon(icon, size: 13, color: selected ? AppTheme.blue : AppTheme.secondaryLabel),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final largest = controller.largest;
    final scanning = controller.scanning;
    final progress = controller.scanTotal <= 0
        ? null
        : (controller.scanDone / controller.scanTotal).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.groupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '共 ${controller.totalCount} 个项目',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                formatBytes(controller.totalBytes),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            scanning
                ? '正在读取文件大小 ${controller.scanDone} / ${controller.scanTotal}'
                : controller.missingCount > 0
                    ? '有 ${controller.missingCount} 项大小未知（可能是 iCloud 里尚未下载的项目）'
                    : '全部 ${controller.knownCount} 个项目的大小已读取',
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryLabel),
          ),
          if (scanning) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: const Color(0xFFE0E0E5),
                color: AppTheme.blue,
              ),
            ),
          ],
          if (!scanning && largest != null) ...[
            const SizedBox(height: 6),
            Text(
              '最大：${largest.displayName} · ${largest.sizeLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF3C3C43)),
            ),
          ],
          if (scanning && progress != null) ...[
            const SizedBox(height: 6),
            Text(
              '首次扫描需要把每个项目的文件大小读一遍，之后会缓存，秒开',
              style: TextStyle(fontSize: 11, color: AppTheme.secondaryLabel.withValues(alpha: 0.9)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LimitedBanner extends StatelessWidget {
  const _LimitedBanner({required this.onManage});

  final Future<void> Function() onManage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFB26A00)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '当前只能访问部分照片',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A5200)),
            ),
          ),
          TextButton(
            onPressed: () => onManage(),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('管理', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final hasFilter = controller.bucketFilter != null || controller.kindFilter != KindFilter.all;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.filter_alt_off_outlined : Icons.photo_outlined,
            size: 40,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilter ? '当前筛选条件下没有项目' : '相册里还没有照片',
            style: const TextStyle(fontSize: 15, color: AppTheme.secondaryLabel),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                controller.setBucketFilter(null);
                controller.setKindFilter(KindFilter.all);
              },
              child: const Text('清除筛选'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  double get minExtent => 42;

  @override
  double get maxExtent => 42;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white.withValues(alpha: 0.96),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppTheme.secondaryLabel),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) {
    return oldDelegate.title != title || oldDelegate.trailing != trailing;
  }
}
