import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/photo_item.dart';
import '../state/library_controller.dart';
import '../util/format.dart';
import 'theme.dart';

/// 统计页：这个 App 区别于系统相册的地方。
/// 系统相册只告诉你「有几张」，这里告诉你「谁最占地方」。
class StatsTab extends StatelessWidget {
  const StatsTab({
    super.key,
    required this.controller,
    required this.onOpenBucket,
    required this.onOpenItem,
  });

  final LibraryController controller;
  final ValueChanged<SizeBucket?> onOpenBucket;
  final ValueChanged<PhotoItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final stats = controller.buildBucketStats();
    final top = controller.topLargest(10);
    final totalKnown = controller.knownCount;
    final average = totalKnown == 0 ? 0 : controller.totalBytes ~/ totalKnown;
    var maxCount = 0;
    for (final entry in stats.values) {
      if (entry.count > maxCount) maxCount = entry.count;
    }

    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          scrolledUnderElevation: 0.5,
          title: Text('统计'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.groupedBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _Metric(value: '${controller.totalCount}', label: '项目'),
                  _divider(),
                  _Metric(value: formatBytes(controller.totalBytes), label: '合计占用'),
                  _divider(),
                  _Metric(value: formatBytes(average), label: '平均大小'),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Notice(
            text: controller.missingCount > 0
                ? '还有 ${controller.missingCount} 个项目的大小没读到，'
                    '它们暂时排在列表最后。可在「图库 › 更多」里重新扫描。'
                : '全部项目的大小已读取完毕，数据缓存在本机，下次打开秒开。',
          ),
        ),
        const SliverToBoxAdapter(child: _Heading('大小分布')),
        for (final bucket in [...SizeBucket.all, SizeBucket.unknown])
          SliverToBoxAdapter(
            child: _BucketBar(
              bucket: bucket,
              count: stats[bucket.id]?.count ?? 0,
              bytes: stats[bucket.id]?.bytes ?? 0,
              maxCount: maxCount,
              onTap: () => onOpenBucket(bucket == SizeBucket.unknown ? null : bucket),
            ),
          ),
        const SliverToBoxAdapter(child: _Heading('最占空间的 10 个项目')),
        if (top.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Text(
                '暂无数据。等文件大小读取完成后这里会列出最大的项目。',
                style: TextStyle(fontSize: 13, color: AppTheme.secondaryLabel),
              ),
            ),
          )
        else
          for (var i = 0; i < top.length; i++)
            SliverToBoxAdapter(
              child: _TopRow(
                rank: i + 1,
                item: top[i],
                onTap: () => onOpenItem(top[i]),
              ),
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  Widget _divider() => Container(width: 0.5, height: 28, color: AppTheme.separator);
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.secondaryLabel)),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5EBF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 15, color: AppTheme.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF3C3C43)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BucketBar extends StatelessWidget {
  const _BucketBar({
    required this.bucket,
    required this.count,
    required this.bytes,
    required this.maxCount,
    required this.onTap,
  });

  final SizeBucket bucket;
  final int count;
  final int bytes;
  final int maxCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);

    return InkWell(
      onTap: count == 0 ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    bucket.label,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 10,
                      backgroundColor: AppTheme.groupedBackground,
                      color: AppTheme.blue.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 46,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  width: 66,
                  child: Text(
                    formatBytes(bytes),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.secondaryLabel,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.rank, required this.item, required this.onTap});

  final int rank;
  final PhotoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.separator, width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryLabel,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${formatDate(item.created)} · ${item.dimensionLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppTheme.secondaryLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.sizeLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}
