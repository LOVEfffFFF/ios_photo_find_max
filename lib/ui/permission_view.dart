import 'package:flutter/material.dart';

import 'theme.dart';

/// 没拿到相册权限时的整页引导。
///
/// 拒绝之后 iOS 不会再弹系统授权框，只能引导用户去「设置」；
/// 这一点必须写清楚，否则界面会变成「点了没反应」。
class PermissionView extends StatelessWidget {
  const PermissionView({
    super.key,
    required this.status,
    required this.busy,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final String status;
  final bool busy;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final denied = status == 'denied' || status == 'restricted';
    final unsupported = status == 'unsupported';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppTheme.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 24),
              Text(
                unsupported
                    ? '仅支持 iOS'
                    : denied
                        ? '无法访问相册'
                        : '允许访问你的照片',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                unsupported
                    ? '这个 App 的相册能力由 iOS 原生 PhotoKit 提供，只能在 iPhone / iPad 上运行。'
                    : denied
                        ? '你之前拒绝了相册权限。请到「设置 › 隐私与安全性 › 照片」中允许本 App 访问。'
                        : '为了按文件大小列出照片和视频，本 App 需要读取你的相册。\n'
                            '读取的内容只在你的手机上处理，不会上传到任何地方。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Color(0xFF3C3C43),
                ),
              ),
              const SizedBox(height: 28),
              if (!unsupported)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : (denied ? onOpenSettings : onRequest),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.blue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            denied ? '打开设置' : '允许访问照片',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                '浏览是只读的；只有你主动点「删除」并确认，项目才会移到系统「最近删除」。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.5, color: AppTheme.secondaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
