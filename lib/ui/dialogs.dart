import 'package:flutter/material.dart';

import 'theme.dart';

/// 删除确认 —— 文案与系统「照片」App 一致：
/// 删除不是立刻抹掉，而是进「最近删除」，30 天后由系统清掉。
Future<bool> confirmDelete(BuildContext context, int count) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      title: Text(count > 1 ? '删除 $count 个项目？' : '删除这个项目？'),
      content: const Text(
        '这些项目将移到「最近删除」相簿，30 天后自动永久删除。\n'
        '在系统「照片」App 的「最近删除」里可以恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: AppTheme.blue, fontSize: 16)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '删除',
            style: TextStyle(color: AppTheme.red, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 把删除结果如实告诉用户：删了几个、失败几个、为什么失败。
void showDeleteResult(
  BuildContext context, {
  required int deleted,
  required int failed,
  String? error,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  if (deleted == 0) {
    messenger.showSnackBar(SnackBar(
      content: Text(error == null || error.isEmpty ? '删除失败' : '删除失败：$error'),
    ));
    return;
  }
  final buffer = StringBuffer('已删除 $deleted 个项目，可在「最近删除」中恢复');
  if (failed > 0) buffer.write('；$failed 个失败');
  messenger.showSnackBar(SnackBar(content: Text(buffer.toString())));
}

void showToast(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// 底部弹出的操作表，视觉上和 iOS 的 action sheet 一致
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<ActionSheetItem<T>> items,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: AppTheme.secondaryLabel),
                      ),
                    ),
                    const Divider(height: 0.5, thickness: 0.5, color: AppTheme.separator),
                    for (final item in items) ...[
                      InkWell(
                        onTap: () => Navigator.of(context).pop(item.value),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 17,
                              color: item.destructive ? AppTheme.red : AppTheme.blue,
                              fontWeight: item.destructive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      if (item != items.last)
                        const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          indent: 16,
                          color: AppTheme.separator,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 17, color: AppTheme.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ActionSheetItem<T> {
  const ActionSheetItem({required this.label, required this.value, this.destructive = false});

  final String label;
  final T value;
  final bool destructive;
}
