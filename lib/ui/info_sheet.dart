import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/asset_detail.dart';
import '../models/photo_item.dart';
import '../services/photo_library_api.dart';
import '../util/format.dart';
import 'theme.dart';

/// 弹出的「详细信息」面板 —— 对应系统相册里那个 ⓘ 面板。
///
/// 先用手上已有的数据立刻渲染，再异步补齐原生详情（位置地名、相簿、资源明细），
/// 这样点开是「秒开」，而不是先转两秒圈才出内容。
Future<void> showInfoSheet(BuildContext context, PhotoItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _InfoSheet(item: item),
  );
}

class _InfoSheet extends StatefulWidget {
  const _InfoSheet({required this.item});

  final PhotoItem item;

  @override
  State<_InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<_InfoSheet> {
  AssetDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await const PhotoLibraryApi().assetDetail(widget.item.id);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final detail = _detail;
    final height = MediaQuery.sizeOf(context).height * 0.82;

    final rows = <Widget>[];

    // —— 文件 ——
    rows.add(const _SectionTitle('文件'));
    rows.add(_InfoRow(label: '文件大小', value: detail?.sizeLabel ?? item.sizeLabel, emphasize: true));
    if (detail != null) {
      rows.add(_InfoRow(label: '尺寸', value: '${detail.dimensionLabel}  ${detail.megapixelLabel}'));
    } else {
      rows.add(_InfoRow(label: '尺寸', value: item.dimensionLabel));
    }
    rows.add(_InfoRow(label: '类型', value: detail?.typeLabel ?? item.kind.label));
    rows.add(_InfoRow(label: '文件名', value: item.displayName));
    if (detail != null && detail.uti.isNotEmpty) {
      rows.add(_InfoRow(label: '文件格式', value: detail.uti));
    }
    if (detail != null && detail.hasAdjustments) {
      rows.add(const _InfoRow(label: '编辑', value: '已应用过编辑（保留原始数据）'));
    }
    if (item.isVideo) {
      rows.add(_InfoRow(label: '时长', value: formatDuration(item.duration)));
    }
    rows.add(_InfoRow(
      label: '大小来源',
      value: _sourceLabel(detail?.sizeSource ?? item.sizeSource),
    ));

    // —— 时间 ——
    rows.add(const _SectionTitle('时间'));
    rows.add(_InfoRow(label: '拍摄时间', value: formatDate(item.created)));
    rows.add(_InfoRow(label: '修改时间', value: formatDate(item.modified)));
    if (detail != null) {
      rows.add(_InfoRow(label: '所属来源', value: detail.sourceName));
    }

    // —— 位置 ——
    rows.add(const _SectionTitle('位置'));
    rows.add(_InfoRow(
      label: '地点',
      value: detail == null ? '读取中…' : detail.placeLabel,
    ));
    if (detail != null && detail.hasLocation) {
      rows.add(_InfoRow(
        label: '坐标',
        value: formatCoordinates(detail.latitude, detail.longitude),
      ));
    }

    // —— 相簿 ——
    if (detail != null && detail.albums.isNotEmpty) {
      rows.add(const _SectionTitle('相簿'));
      for (final album in detail.albums) {
        rows.add(_InfoRow(label: '相簿', value: album));
      }
    }

    // —— 资源明细 ——
    if (detail != null && detail.resources.isNotEmpty) {
      rows.add(_SectionTitle('资源明细（${detail.resources.length} 份文件）'));
      for (final resource in detail.resources) {
        rows.add(_ResourceRow(resource: resource));
      }
      if (detail.resources.length > 1) {
        rows.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            '实况照片、ProRAW、已编辑的照片在相册里可能挂着多份文件，'
            '上面列的是它们的实际构成。',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: AppTheme.secondaryLabel),
          ),
        ));
      }
    }

    // —— 标识符 ——
    rows.add(const _SectionTitle('标识符'));
    rows.add(
      _InfoRow(
        label: 'localIdentifier',
        value: widget.item.id,
        trailing: IconButton(
          tooltip: '复制',
          icon: const Icon(Icons.copy_rounded, size: 16),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.item.id));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制标识符')),
            );
          },
        ),
      ),
    );

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D1D6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.sizeLabel} · ${item.kind.label}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.secondaryLabel),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'meta':
        return '系统元数据（各资源 fileSize 合计）';
      case 'read':
        return '逐文件读取字节数';
      case 'partial':
        return '部分资源读取失败，可能偏小';
      default:
        return '尚未读取';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.groupedBackground,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppTheme.secondaryLabel,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.separator, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.secondaryLabel, height: 1.4),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 14 : 13,
                height: 1.4,
                fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: emphasize ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.resource});

  final AssetResourceDetail resource;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.separator, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 1),
                Text(
                  resource.filename.isEmpty ? resource.uti : resource.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.secondaryLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            resource.sizeLabel,
            style: const TextStyle(
              fontSize: 12.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
