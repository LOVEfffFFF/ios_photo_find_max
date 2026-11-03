import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/photo_library_api.dart';
import '../state/library_controller.dart';
import 'dialogs.dart';
import 'theme.dart';

/// 帮助 / 关于页。写清楚三件容易误解的事：
/// 大小怎么算的、删掉去哪了、为什么有些项目显示「…」。
class HelpTab extends StatelessWidget {
  const HelpTab({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          scrolledUnderElevation: 0.5,
          title: Text('说明'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.blue,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        AppInfo.name,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '版本 ${AppInfo.display}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.secondaryLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: _Section('这个 App 做什么')),
        const SliverToBoxAdapter(
          child: _Paragraph(
            '把相册里的照片和视频按「文件大小」从大到小排开，方便找出最占空间的那几个。\n'
            '排序、翻页、收藏、详细信息、删除都照系统「照片」App 的操作习惯来做。',
          ),
        ),

        const SliverToBoxAdapter(child: _Section('文件大小是怎么算的')),
        const SliverToBoxAdapter(
          child: _Paragraph(
            '大小是这个项目在相册里全部文件的合计：\n'
            '· 普通照片：原图一个文件\n'
            '· 实况照片：照片 + 配对视频\n'
            '· ProRAW：DNG + 渲染图 + 编辑数据\n'
            '· 已编辑的照片：原图 + 渲染结果\n\n'
            '首次打开会把每个项目读一遍，之后结果缓存在手机里，再打开就不用重算。'
            'iCloud 里还没下载到本机的项目，如果系统连元数据都取不到，会显示成「…」并排在最后。',
          ),
        ),

        const SliverToBoxAdapter(child: _Section('删除会去哪')),
        const SliverToBoxAdapter(
          child: _Paragraph(
            '和系统相册完全一样：删除后进入「最近删除」相簿，30 天后由系统自动永久清除。\n'
            '想恢复就去系统「照片」App › 相簿 › 最近删除，选中后点「恢复」。\n\n'
            '本 App 只有「删除」这一个会改动相册的操作，且必须你点确认才会执行 —— '
            '浏览、排序、查看信息都是只读的。',
          ),
        ),

        const SliverToBoxAdapter(child: _Section('操作')),
        SliverToBoxAdapter(
          child: _ActionTile(
            icon: Icons.refresh,
            title: '重新扫描文件大小',
            subtitle: '相册有变动、或想强制重算时用',
            onTap: () async {
              controller.clearImageCaches();
              await controller.refresh(forceRescan: true);
              if (!context.mounted) return;
              showToast(context, '扫描已重新开始');
            },
          ),
        ),
        if (controller.isLimited)
          SliverToBoxAdapter(
            child: _ActionTile(
              icon: Icons.lock_open_outlined,
              title: '管理可访问的照片',
              subtitle: '当前是「部分访问」，可以在这里加选更多照片',
              onTap: () => const PhotoLibraryApi().presentLimitedPicker(),
            ),
          ),
        SliverToBoxAdapter(
          child: _ActionTile(
            icon: Icons.settings_outlined,
            title: '打开系统设置',
            subtitle: '修改相册权限',
            onTap: () => const PhotoLibraryApi().openSettings(),
          ),
        ),
        SliverToBoxAdapter(
          child: _ActionTile(
            icon: Icons.cleaning_services_outlined,
            title: '清空图片缓存',
            subtitle: '只清缩略图内存缓存，不影响任何照片',
            onTap: () {
              controller.clearImageCaches();
              showToast(context, '图片缓存已清空');
            },
          ),
        ),
        SliverToBoxAdapter(
          child: SwitchListTile.adaptive(
            value: controller.includeHidden,
            onChanged: controller.setIncludeHidden,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('显示已隐藏的项目', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '系统「照片」默认不显示已隐藏的项目，打开后会一并列出',
              style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryLabel),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: _Section('运行数据')),
        SliverToBoxAdapter(
          child: _Paragraph(
            '相册项目：${controller.totalCount} 个\n'
            '已读到大小：${controller.knownCount} 个\n'
            '大小未知：${controller.missingCount} 个\n'
            '数据来源：${_sourceLabel(controller.sizeSource)}',
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'meta':
        return '系统元数据（fileSize）';
      case 'read':
        return '逐文件读取字节数';
      case 'partial':
        return '部分读取成功';
      default:
        return '尚未扫描';
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.secondaryLabel),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, height: 1.65, color: Color(0xFF3C3C43)),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.separator, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppTheme.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.secondaryLabel),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}
