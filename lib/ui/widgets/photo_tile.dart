import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../models/photo_item.dart';
import '../../services/thumbnail_loader.dart';
import '../../util/format.dart';
import '../theme.dart';

/// 图库网格里的一格。方图、无圆角、右下角标文件大小 ——
/// 这套视觉来自系统「照片」App 的网格，只是多了一个大小角标。
class PhotoTile extends StatefulWidget {
  const PhotoTile({
    super.key,
    required this.item,
    required this.thumbPx,
    required this.onTap,
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final PhotoItem item;
  final int thumbPx;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<PhotoTile> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.thumbPx != widget.thumbPx) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final bytes = await ThumbnailLoader.instance.load(widget.item.id, widget.thumbPx);
    if (!mounted) return;
    if (bytes != null) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: const Color(0xFFE9E9EE)),
          if (_bytes != null)
            Image.memory(
              _bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (context, error, stack) => _placeholder(),
            )
          else
            _placeholder(),

          // 视频：左上角时长 + 播放小图标（系统相册同款）
          if (item.isVideo)
            Positioned(
              left: 5,
              top: 5,
              child: Row(
                children: [
                  const Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 1),
                  Text(
                    formatDurationShort(item.duration),
                    style: _badgeText,
                  ),
                ],
              ),
            ),

          // 实况照片：系统用 LIVE 角标，这里保持一致
          if (item.isLive && !item.isVideo)
            Positioned(
              left: 5,
              top: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('LIVE', style: _badgeText.copyWith(fontSize: 8, letterSpacing: 0.4)),
              ),
            ),

          // 收藏 / 已隐藏
          if (item.isFavorite || item.isHidden)
            Positioned(
              left: 5,
              bottom: 5,
              child: Row(
                children: [
                  if (item.isFavorite)
                    const Icon(Icons.favorite, size: 11, color: Colors.white),
                  if (item.isHidden)
                    const Padding(
                      padding: EdgeInsets.only(left: 3),
                      child: Icon(Icons.visibility_off, size: 11, color: Colors.white),
                    ),
                ],
              ),
            ),

          // 文件大小角标：这个 App 的主角
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.bytesKnown ? formatBytes(item.bytes) : '…',
                style: _badgeText.copyWith(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),

          if (widget.selecting)
            Positioned(
              right: 5,
              top: 5,
              child: _SelectionDot(selected: widget.selected),
            ),

          // 选中时整体压暗一点，和系统相册的选择态一致
          if (widget.selected)
            IgnorePointer(
              child: Container(color: Colors.white.withValues(alpha: 0.28)),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        widget.item.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        size: 22,
        color: Colors.black26,
      ),
    );
  }
}

const TextStyle _badgeText = TextStyle(
  color: Colors.white,
  fontSize: 10,
  fontWeight: FontWeight.w500,
  height: 1.1,
  shadows: [Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 0.5))],
);

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 21,
      height: 21,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppTheme.blue : Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      child: selected
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}
