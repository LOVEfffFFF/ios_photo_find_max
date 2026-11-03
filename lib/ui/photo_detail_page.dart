import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/photo_item.dart';
import '../services/thumbnail_loader.dart';
import '../state/library_controller.dart';
import '../util/format.dart';
import 'dialogs.dart';
import 'info_sheet.dart';

/// 全屏查看页。左右滑动在**当前排序结果**里翻页 ——
/// 所以从「100 MB 以上」分组点进来，划到的都是同量级的大文件。
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({
    super.key,
    required this.controller,
    this.initialIndex = 0,
  });

  final LibraryController controller;
  final int initialIndex;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late final PageController _pageController;
  late int _index;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final items = widget.controller.visible;
        if (items.isEmpty) {
          // 删到一张不剩时退回图库
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(backgroundColor: Colors.black);
        }

        final index = _index.clamp(0, items.length - 1);
        final item = items[index];

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: items.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, i) => _PreviewPage(
                  key: ValueKey<String>(items[i].id),
                  item: items[i],
                  onTap: _toggleChrome,
                ),
              ),
              if (_chromeVisible) ...[
                _TopBar(
                  item: item,
                  position: '${index + 1} / ${items.length}',
                  onClose: () => Navigator.of(context).maybePop(),
                ),
                _BottomBar(
                  item: item,
                  onFavorite: () async {
                    final ok = await widget.controller
                        .setFavorite(item.id, !item.isFavorite);
                    if (!ok && mounted) {
                      showToast(context, '修改收藏失败');
                    }
                  },
                  onInfo: () => showInfoSheet(context, item),
                  onDelete: () => _deleteCurrent(items, index),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  Future<void> _deleteCurrent(List<PhotoItem> items, int index) async {
    final item = items[index];
    final confirmed = await confirmDelete(context, 1);
    if (!confirmed || !mounted) return;

    final result = await widget.controller.deleteIds([item.id]);
    if (!mounted) return;
    showDeleteResult(
      context,
      deleted: result.deleted,
      failed: result.failed,
      error: result.error,
    );
    if (widget.controller.visible.isEmpty && mounted) {
      Navigator.of(context).maybePop();
    }
  }
}

class _PreviewPage extends StatefulWidget {
  const _PreviewPage({super.key, required this.item, required this.onTap});

  final PhotoItem item;
  final VoidCallback onTap;

  @override
  State<_PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<_PreviewPage> {
  final TransformationController _transform = TransformationController();
  Uint8List? _bytes;
  bool _loading = true;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bytes = await PreviewLoader.instance.load(widget.item.id);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  void _handleDoubleTap() {
    if (!_transform.value.isIdentity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    const scale = 2.6;
    final position = _doubleTapPosition;
    _transform.value = Matrix4.identity()
      ..translate(-position.dx * (scale - 1), -position.dy * (scale - 1))
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_bytes != null)
            InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  _bytes!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => _errorView(),
                ),
              ),
            )
          else if (_loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
              ),
            )
          else
            _errorView(),

          if (widget.item.isVideo)
            Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_outlined, size: 13, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        '视频封面 · ${formatDurationShort(widget.item.duration)}',
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white30, size: 36),
          SizedBox(height: 8),
          Text('无法载入这个项目', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.item,
    required this.position,
    required this.onClose,
  });

  final PhotoItem item;
  final String position;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer(formatDate(item.created));
    if (item.isVideo) subtitle.write(' · 视频 ${formatDurationShort(item.duration)}');
    if (item.isLive) subtitle.write(' · 实况');

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 22),
            child: Row(
              children: [
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 30),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  position,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.item,
    required this.onFavorite,
    required this.onInfo,
    required this.onDelete,
  });

  final PhotoItem item;
  final Future<void> Function() onFavorite;
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 26, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BarButton(
                  icon: item.isFavorite ? Icons.favorite : Icons.favorite_border,
                  label: item.isFavorite ? '已收藏' : '收藏',
                  onTap: onFavorite,
                ),
                _BarButton(icon: Icons.info_outline, label: '信息', onTap: onInfo),
                _BarButton(
                  icon: Icons.delete_outline,
                  label: '删除',
                  onTap: onDelete,
                  color: const Color(0xFFFF6B60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
