# 大小相册（PhotoSize）

一个「照抄 iOS 原生相册、但按文件大小排序」的 iPhone App。用来快速找出相册里最占空间的照片和视频。

- 网格按文件大小从大到小分组（100 MB 以上 / 50–100 MB / … / 小于 100 KB）
- 可以切换「小到大」「按日期」，可以只看照片或只看视频
- 点开全屏查看，支持双指缩放、左右滑动
- ⓘ 详细信息：文件名、分辨率、文件大小、拍摄/修改时间、位置、相簿、**资源明细**（实况照片的配对视频、ProRAW 的 DNG + 渲染图 + 编辑数据各占多少）
- 长按进入多选，可批量删除；删除与系统相册一致，进「最近删除」，30 天后由系统清除
- 统计页：各大小区间的数量与占用、最占空间的 10 个项目

## 目录

```
lib/                      Flutter 界面与状态
  services/photo_library_api.dart   原生通道封装（唯一与 iOS 交互的地方）
  state/library_controller.dart     排序、筛选、分组、扫描进度
  ui/                               图库 / 详情 / 信息面板 / 统计 / 说明
ios/Runner/AppDelegate.swift        PhotoKit 桥（读取大小、缩略图、详情、删除）
.github/workflows/build_ios.yml     CI：在 macOS runner 上编译出未签名 IPA
```

## 技术要点

**文件大小怎么来.** `PHAssetResource` 没有公开的 size 属性。主路径是 KVC 读 `fileSize`，
但 KVC 读到不存在的 key 会抛 Objective-C 异常（Swift 接不住、直接闪退），
所以先用 `responds(to:)` 探针确认 getter 存在再读；探针失败时退回
`PHAssetResourceManager.requestData` 逐字节计数（不保留内容、不写盘）。
结果按 `localIdentifier + 修改时间` 缓存在 `Documents/photo_size_cache.json`，
第二次启动直接读缓存，两万张也是秒开。

**大小是合计值.** Live Photo 算「照片 + 配对视频」，ProRAW 算「DNG + 渲染图 + 编辑数据」，
和系统「照片」详情里的数字同口径 —— 否则会严重低估占用。

**删除是系统删除.** `PHAssetChangeRequest.deleteAssets` 走的就是系统相册的删除通道，
照片进「最近删除」而不是立刻消失。App 内先给一次确认（文案与系统一致），
原生侧还强制要求 `confirm=true`，口子做窄。

**没有第三方依赖.** 权限、缩略图、详情、删除全部走自己写的 MethodChannel / EventChannel，
不引 `photo_manager` / `permission_handler`，少一层 CI 变数。

## 构建（GitHub Actions）

Windows 上没有 Flutter SDK / macOS，本地编不了 iOS。流程固定：

1. 推送代码到 `main`
2. 手动触发（`push` 事件产出的 workflow 不带 IPA）：

   ```bash
   gh workflow run build_ios.yml -R <owner>/ios_photo_find_max -f build_type=release
   ```

3. 等 `gh run watch` 结束后取产物：

   ```bash
   gh run download <run-id> -R <owner>/ios_photo_find_max -n PhotoSize-<sha>
   ```

CI 里 `flutter create --platforms=ios ...` 只补齐缺失的工程文件（pbxproj、storyboard），
仓库里已有的 `ios/Runner/AppDelegate.swift` 与 `Info.plist` 不会被覆盖 —— 原生桥靠这个进包。
Deployment target 在 CI 里被改成 17.0，签名全部关闭。

## 安装（自己操作）

IPA 是**未签名**的，需要用你自己的 Apple ID 重签后装进手机，推荐 Sideloadly：

1. 电脑装好 iTunes / Apple Devices（提供 Apple Mobile Device 服务与驱动）
2. iPhone 用数据线连电脑，解锁并点「信任」
3. 打开 Sideloadly，把 `PhotoSize.ipa` 拖进去，Apple ID 填自己的，Start
4. 手机上：设置 › 通用 › VPN与设备管理 › 信任该开发者
5. 首次打开会弹相册权限，选「允许访问所有照片」

免费 Apple ID 签的 App 7 天过期，过期后重装一次即可（照片数据在系统相册里，不随 App 卸载丢失）。

## 产物位置

编译完成后 IPA 固定放在 `C:\Users\OXO\Desktop\ios_photo_find_max\PhotoSize.ipa`（未签名）。
校验方法：解包后 `Payload/Runner.app/Frameworks/App.framework/App` 里能搜到
`com.photosize/photolib`（Dart 侧通道名），`Payload/Runner.app/Runner` 里能搜到
`photo_size_cache.json`（原生侧缓存文件名）。

## 已知限制

- 视频只显示封面帧，不播放（本 App 的定位是「按大小找文件」）
- iCloud 里未下载且连元数据都取不到的项目，大小显示为「…」并排在最后
- 删除后 App 内不提供「最近删除」列表（系统不公开该相簿的读取接口），请到系统「照片」App 里恢复
- 只支持 iOS 17+，只在 iPhone 竖屏下验证
