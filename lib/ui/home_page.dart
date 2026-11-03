import 'package:flutter/material.dart';

import '../models/photo_item.dart';
import '../services/photo_library_api.dart';
import '../state/library_controller.dart';
import 'dialogs.dart';
import 'help_tab.dart';
import 'info_sheet.dart';
import 'library_tab.dart';
import 'permission_view.dart';
import 'photo_detail_page.dart';
import 'stats_tab.dart';
import 'theme.dart';

/// 外壳：三个页签 + 权限门 + 多选工具条。
///
/// 页签设计对应系统「照片」底部那排：图库 / 统计 / 说明。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final LibraryController _controller = LibraryController();
  int _tab = 0;
  bool _busyPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleControllerMessage);
    _controller.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerMessage);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 从「设置」改完权限、或在系统相册里删了照片回来，都要重新同步
    if (_controller.hasAccess) {
      _controller.refresh(silent: true);
    } else {
      _controller.init();
    }
  }

  void _handleControllerMessage() {
    final message = _controller.message;
    if (message == null || message.isEmpty) return;
    _controller.clearMessage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showToast(context, message);
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _busyPermission = true);
    await _controller.requestPermission();
    if (!mounted) return;
    setState(() => _busyPermission = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.hasAccess) {
          if (_controller.initializing) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return PermissionView(
            status: _controller.status,
            busy: _busyPermission,
            onRequest: _requestPermission,
            onOpenSettings: () => const PhotoLibraryApi().openSettings(),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              IndexedStack(
                index: _tab,
                children: [
                  LibraryTab(controller: _controller),
                  StatsTab(
                    controller: _controller,
                    onOpenBucket: (bucket) {
                      _controller.setBucketFilter(bucket);
                      setState(() => _tab = 0);
                    },
                    onOpenItem: (item) => _openItem(item),
                  ),
                  HelpTab(controller: _controller),
                ],
              ),
              if (_controller.initializing && _controller.allItems.isEmpty)
                const ColoredBox(
                  color: Colors.white,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
          bottomNavigationBar:
              _controller.selecting ? _selectionBar() : _bottomBar(),
        );
      },
    );
  }

  void _openItem(PhotoItem item) {
    _controller.setBucketFilter(null);
    _controller.setKindFilter(KindFilter.all);
    final index = _controller.visible.indexWhere((e) => e.id == item.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoDetailPage(
          controller: _controller,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(top: BorderSide(color: AppTheme.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              _TabItem(
                icon: Icons.photo_library_outlined,
                activeIcon: Icons.photo_library,
                label: '图库',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _TabItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart,
                label: '统计',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
              _TabItem(
                icon: Icons.info_outline,
                activeIcon: Icons.info,
                label: '说明',
                selected: _tab == 2,
                onTap: () => setState(() => _tab = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar() {
    final count = _controller.selected.length;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF2FFFFFF),
        border: Border(top: BorderSide(color: AppTheme.separator, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              _SelectAction(
                icon: Icons.done_all,
                label: '全选',
                onTap: _controller.selectAllVisible,
              ),
              _SelectAction(
                icon: Icons.delete_outline,
                label: '删除',
                color: AppTheme.red,
                onTap: () => _deleteSelected(),
              ),
              _SelectAction(
                icon: Icons.info_outline,
                label: '信息',
                enabled: count == 1,
                onTap: () => _showSelectedInfo(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final ids = _controller.selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await confirmDelete(context, ids.length);
    if (!confirmed || !mounted) return;
    final result = await _controller.deleteIds(ids);
    if (!mounted) return;
    showDeleteResult(
      context,
      deleted: result.deleted,
      failed: result.failed,
      error: result.error,
    );
  }

  void _showSelectedInfo() {
    if (_controller.selected.length != 1) return;
    final id = _controller.selected.first;
    final index = _controller.allItems.indexWhere((e) => e.id == id);
    if (index < 0) {
      showToast(context, '这个项目已经不在相册里了');
      return;
    }
    showInfoSheet(context, _controller.allItems[index]);
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.blue : const Color(0xFF8E8E93);
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SelectAction extends StatelessWidget {
  const _SelectAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppTheme.blue,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effective = enabled ? color : const Color(0xFFC7C7CC);
    return Expanded(
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 32,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: effective),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: effective)),
          ],
        ),
      ),
    );
  }
}
