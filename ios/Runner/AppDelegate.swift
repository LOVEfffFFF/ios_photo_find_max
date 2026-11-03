import CoreLocation
import Flutter
import Photos
import UIKit

/// 相册浏览器的原生桥。
///
/// 只做四件事，全部是**只读**的（删除除外，删除是用户显式点确认后才走）：
///   1. 列出相册里的资产（含每个资产的文件大小）
///   2. 取缩略图 / 大图（JPEG 字节，Flutter 侧解码）
///   3. 取单个资产的详细信息（文件名、尺寸、时间、位置、资源明细）
///   4. 删除资产 —— 底层是系统相册的删除，照片进入「最近删除」，30 天后才真正消失
///
/// ## 文件大小从哪来
/// `PHAssetResource` 没有公开的 size 属性。两条路：
///   · 主路径：KVC 读 `fileSize`。**必须先 responds(to:) 探针**，
///     因为 KVC 读不存在的 key 抛的是 Objective-C 异常，Swift 接不住，直接闪退。
///   · 兜底：`PHAssetResourceManager.requestData` 把字节读一遍只累加长度，
///     不保留内容、不写盘。慢，但一定拿得到（iCloud 未下载的资产会失败）。
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler, PHPhotoLibraryChangeObserver {

    // MARK: - 通道与全局状态

    private var libraryChannel: FlutterMethodChannel?
    private var progressChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    /// 缩略图请求统一走这个 manager，它自带一份解码缓存
    private let imageManager = PHCachingImageManager()

    /// 所有耗时操作都排在这条串行队列上：PHAsset 的读取本身线程安全，
    /// 但 `assets` / `sizeCache` 两个字典不是，串行队列让状态只有一份。
    private let workQueue = DispatchQueue(label: "com.photosize.work", qos: .userInitiated)

    /// localIdentifier → PHAsset（只在 workQueue 上写，读时加锁）
    private var assets: [String: PHAsset] = [:]
    private let assetLock = NSLock()

    /// 文件大小缓存：id → ["b": 字节, "m": 修改时间, "s": 来源, "n": 文件名]
    /// 有了它第二次启动不用再算一遍（两万张照片要算十几秒）
    ///
    /// 扫描在 workQueue 上写、详情页在主线程读，所以读写都要过 [cacheLock]。
    private var sizeCache: [String: [String: Any]] = [:]
    private let cacheLock = NSLock()
    private var cacheDirty = false
    /// 距上次落盘又新增了多少条（攒够一批再写，避免每 200 张小图就写一次 JSON）
    private var unsavedRecords = 0

    /// 上一次 loadAssets 是否包含隐藏项目（扫描时要用同一套过滤条件）
    private var lastIncludeHidden = false

    /// 正在扫描，避免重复启动
    private var scanning = false

    /// 最近一次拿大小用的是哪条路径，界面上如实展示
    private var lastSizeSource = ""

    // MARK: - 生命周期

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        loadSizeCache()

        // 相册被别处改动（用户在系统相册里删了照片、或改完「部分访问」的选图）
        // 时通知 Flutter 重新同步，避免界面里还挂着已经不存在的项目。
        // 必须用官方的 register 接口：直接监听同名通知收不到。
        PHPhotoLibrary.shared().register(self)

        if let controller = window?.rootViewController as? FlutterViewController {
            let messenger = controller.binaryMessenger
            libraryChannel = FlutterMethodChannel(
                name: "com.photosize/photolib",
                binaryMessenger: messenger
            )
            libraryChannel?.setMethodCallHandler(handleLibraryCall)

            progressChannel = FlutterEventChannel(
                name: "com.photosize/progress",
                binaryMessenger: messenger
            )
            progressChannel?.setStreamHandler(self)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    /// PHPhotoLibraryChangeObserver —— 相册内容变化回调（可能在后台队列）
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        emit(["type": "libraryChanged"])
    }

    /// 事件必须从主线程发出去
    private func emit(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(payload)
        }
    }

    // MARK: - 方法分发

    private func handleLibraryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "authorizationStatus":
            result(["status": statusString(PHPhotoLibrary.authorizationStatus(for: .readWrite))])
        case "requestAuthorization":
            requestAuthorization(result: result)
        case "loadAssets":
            loadAssets(call: call, result: result)
        case "computeSizes":
            computeSizes(call: call, result: result)
        case "thumbnail":
            requestImage(call: call, result: result, square: true, defaultPx: 300, defaultQuality: 0.82)
        case "preview":
            requestImage(call: call, result: result, square: false, defaultPx: 1600, defaultQuality: 0.9)
        case "assetDetail":
            assetDetail(call: call, result: result)
        case "deleteAssets":
            deleteAssets(call: call, result: result)
        case "setFavorite":
            setFlag(call: call, result: result, favorite: true)
        case "setHidden":
            setFlag(call: call, result: result, favorite: false)
        case "openSettings":
            openSettings(result: result)
        case "presentLimitedPicker":
            presentLimitedPicker(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 权限

    private func statusString(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .limited: return "limited"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private func hasReadAccess() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private func requestAuthorization(result: @escaping FlutterResult) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                result(["status": self.statusString(status)])
            }
        }
    }

    private func openSettings(result: @escaping FlutterResult) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
        }
    }

    /// 「部分访问」时引导用户去改权限。
    ///
    /// 不用 `PHPhotoLibrary.presentLimitedLibraryPicker(from:)`：当前 Xcode SDK
    /// 里已经没有这个成员（CI 编译报 no member）。退回打开本 App 的设置页，
    /// 用户可以在那里把相册权限改成「完整访问」或重新勾选可访问的照片。
    private func presentLimitedPicker(result: @escaping FlutterResult) {
        openSettings(result: result)
    }

    // MARK: - 资产列表

    /// 返回的每一行是**数组**而不是字典：
    /// 两万张照片用字典序列化又慢又占内存，扁平数组小一个数量级。
    /// 下标含义见 `lib/services/photo_library_api.dart` 里的 `_parseRow`。
    private func loadAssets(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard hasReadAccess() else {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            result([
                "status": statusString(status),
                "rows": [],
                "count": 0,
                "totalBytes": 0,
                "knownCount": 0,
                "sizeSource": "",
                "includeHidden": false,
            ])
            return
        }

        let args = call.arguments as? [String: Any] ?? [:]
        let includeHidden = args["includeHidden"] as? Bool ?? false
        lastIncludeHidden = includeHidden
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        workQueue.async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeHiddenAssets = includeHidden
            let fetch = PHAsset.fetchAssets(with: options)

            var map: [String: PHAsset] = [:]
            map.reserveCapacity(fetch.count)
            var rows: [[Any]] = []
            rows.reserveCapacity(fetch.count)
            var total: Int64 = 0
            var known = 0

            fetch.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                map[id] = asset
                let modified = asset.modificationDate?.timeIntervalSince1970 ?? 0

                var bytes: Int64 = 0
                var name = ""
                var source = ""
                if let cached = self.cachedEntry(id),
                   let cachedModified = cached["m"] as? NSNumber,
                   abs(cachedModified.doubleValue - modified) < 1.0,
                   let cachedBytes = cached["b"] as? NSNumber,
                   cachedBytes.int64Value > 0 {
                    bytes = cachedBytes.int64Value
                    name = (cached["n"] as? String) ?? ""
                    source = (cached["s"] as? String) ?? ""
                    total += bytes
                    known += 1
                }

                rows.append([
                    id,
                    asset.creationDate?.timeIntervalSince1970 ?? 0,
                    modified,
                    asset.pixelWidth,
                    asset.pixelHeight,
                    asset.duration,
                    self.mediaKindCode(asset),
                    asset.mediaSubtypes.contains(.photoLive) ? 1 : 0,
                    asset.isFavorite ? 1 : 0,
                    asset.isHidden ? 1 : 0,
                    name,
                    bytes,
                    bytes > 0 ? 1 : 0,
                    source,
                ])
            }

            self.storeAssets(map)

            let payload: [String: Any] = [
                "status": self.statusString(status),
                "rows": rows,
                "count": rows.count,
                "totalBytes": total,
                "knownCount": known,
                "sizeSource": self.lastSizeSource,
                "includeHidden": includeHidden,
            ]
            DispatchQueue.main.async { result(payload) }
        }
    }

    private func mediaKindCode(_ asset: PHAsset) -> Int {
        switch asset.mediaType {
        case .image: return 1
        case .video: return 2
        case .audio: return 3
        default: return 0
        }
    }

    // MARK: - 文件大小扫描

    private func computeSizes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard hasReadAccess() else {
            result(["error": "没有相册访问权限"])
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        let force = args["force"] as? Bool ?? false
        let allowNetwork = args["allowNetwork"] as? Bool ?? false

        if scanning {
            result(["started": false, "reason": "already running"])
            return
        }
        scanning = true

        workQueue.async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeHiddenAssets = self.lastIncludeHidden
            let fetch = PHAsset.fetchAssets(with: options)

            let totalCount = fetch.count
            var done = 0
            var totalBytes: Int64 = 0
            var batch: [[Any]] = []
            var sources: Set<String> = []
            var map: [String: PHAsset] = [:]
            map.reserveCapacity(totalCount)

            self.emit([
                "type": "start",
                "total": totalCount,
                "force": force,
            ])

            fetch.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                map[id] = asset
                let modified = asset.modificationDate?.timeIntervalSince1970 ?? 0

                var bytes: Int64 = 0
                var name = ""
                var source = ""

                if !force,
                   let cached = self.cachedEntry(id),
                   let cachedModified = cached["m"] as? NSNumber,
                   abs(cachedModified.doubleValue - modified) < 1.0,
                   let cachedBytes = cached["b"] as? NSNumber,
                   cachedBytes.int64Value > 0 {
                    bytes = cachedBytes.int64Value
                    name = (cached["n"] as? String) ?? ""
                    source = (cached["s"] as? String) ?? ""
                } else {
                    let resources = PHAssetResource.assetResources(for: asset)
                    name = resources.first?.originalFilename ?? ""
                    let measured = Self.measureSize(asset, resources: resources, allowNetwork: allowNetwork)
                    bytes = measured.bytes
                    source = measured.source
                    self.setCachedEntry(id, [
                        "b": NSNumber(value: bytes),
                        "m": NSNumber(value: modified),
                        "s": source,
                        "n": name,
                    ])
                    self.cacheDirty = true
                    self.unsavedRecords += 1
                }

                if !source.isEmpty { sources.insert(source) }
                totalBytes += bytes
                done += 1
                batch.append([id, bytes, name, source])

                if batch.count >= 500 {
                    let chunk = batch
                    batch.removeAll(keepingCapacity: true)
                    self.emit([
                        "type": "batch",
                        "items": chunk,
                        "done": done,
                        "total": totalCount,
                        "totalBytes": totalBytes,
                    ])
                    self.saveSizeCacheIfNeeded(force: false)
                }
            }

            let remaining = batch
            if !remaining.isEmpty {
                self.emit([
                    "type": "batch",
                    "items": remaining,
                    "done": done,
                    "total": totalCount,
                    "totalBytes": totalBytes,
                ])
            }

            self.storeAssets(map)
            self.saveSizeCacheIfNeeded(force: true)

            // 来源只保留一个短标签，界面上直接显示
            if sources.contains("meta") {
                self.lastSizeSource = "meta"
            } else if sources.contains("read") || sources.contains("partial") {
                self.lastSizeSource = "read"
            }

            self.scanning = false
            self.emit([
                "type": "done",
                "done": done,
                "total": totalCount,
                "totalBytes": totalBytes,
                "sizeSource": self.lastSizeSource,
            ])
            DispatchQueue.main.async {
                result([
                    "scanned": done,
                    "total": totalCount,
                    "totalBytes": totalBytes,
                    "sizeSource": self.lastSizeSource,
                ])
            }
        }
    }

    /// 一个资产的**全部**资源合计字节数。
    ///
    /// 为什么合计而不是只取主资源：Live Photo 是「照片 + 配对视频」、
    /// ProRAW 是「DNG + 渲染图 + 编辑指令」，只看主文件会严重低估占用。
    private static func measureSize(
        _ asset: PHAsset,
        resources: [PHAssetResource],
        allowNetwork: Bool
    ) -> (bytes: Int64, source: String) {
        if !resources.isEmpty {
            var sum: Int64 = 0
            var allKnown = true
            for resource in resources {
                if let value = int64Property(resource, "fileSize") {
                    sum += value
                } else {
                    allKnown = false
                    break
                }
            }
            if allKnown && sum > 0 {
                return (sum, "meta")
            }
        }

        // 兜底：读一遍字节数，只累加长度，不保留内容
        var total: Int64 = 0
        var failed = false
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetwork
        for resource in resources {
            let semaphore = DispatchSemaphore(value: 0)
            var ok = false
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { data in
                    total += Int64(data.count)
                },
                completionHandler: { error in
                    ok = (error == nil)
                    semaphore.signal()
                }
            )
            switch semaphore.wait(timeout: .now() + 60) {
            case .timedOut:
                failed = true
            case .success:
                break
            }
            if !ok { failed = true }
        }
        return (total, failed ? "partial" : "read")
    }

    /// 安全地读私有属性：先确认响应 getter，再走 KVC
    ///
    /// `responds(to:)` 为 false 时直接返回 nil —— 这样 KVC 永远不会碰到
    /// 「key 不存在抛 NSUnknownKeyException」那条崩溃路径。
    private static func int64Property(_ object: NSObject, _ key: String) -> Int64? {
        let selector = NSSelectorFromString(key)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.value(forKey: key) as? NSNumber else { return nil }
        return value.int64Value
    }

    // MARK: - 缩略图 / 大图

    private func requestImage(
        call: FlutterMethodCall,
        result: @escaping FlutterResult,
        square: Bool,
        defaultPx: Int,
        defaultQuality: Double
    ) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let asset = asset(for: id) else {
            result(nil)
            return
        }
        let px = (args["px"] as? NSNumber)?.intValue ?? defaultPx
        let quality = (args["quality"] as? NSNumber)?.doubleValue ?? defaultQuality
        let side = CGFloat(max(32, px))

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = square ? .fast : .exact
        options.version = .current

        var replied = false
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: square ? .aspectFill : .aspectFit,
            options: options
        ) { image, info in
            if replied { return }
            if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled { return }
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
            replied = true
            let data = image?.jpegData(compressionQuality: quality)
            DispatchQueue.main.async {
                if let data = data {
                    result(FlutterStandardTypedData(bytes: data))
                } else {
                    result(nil)
                }
            }
        }
    }

    // MARK: - 资产详情

    private func assetDetail(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              !id.isEmpty else {
            result(["error": "参数不完整"])
            return
        }
        guard let asset = asset(for: id) else {
            result(["error": "找不到该照片，可能已被删除"])
            return
        }

        let resources = PHAssetResource.assetResources(for: asset)
        var rows: [[String: Any]] = []
        var resourceBytes: Int64 = 0
        for (index, resource) in resources.enumerated() {
            let bytes = Self.int64Property(resource, "fileSize") ?? 0
            resourceBytes += bytes
            rows.append([
                "index": index,
                "type": Int(resource.type.rawValue),
                "typeName": Self.resourceTypeName(resource.type),
                "uti": resource.uniformTypeIdentifier,
                "filename": resource.originalFilename,
                "bytes": bytes,
            ])
        }

        var albums: [String] = []
        let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
        collections.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle, !title.isEmpty {
                albums.append(title)
            }
        }

        let cached = cachedEntry(id)
        let cachedBytes = (cached?["b"] as? NSNumber)?.int64Value ?? 0

        var info: [String: Any] = [
            "id": id,
            "filename": resources.first?.originalFilename ?? "",
            "uti": resources.first?.uniformTypeIdentifier ?? "",
            "kind": mediaKindCode(asset),
            "playbackStyle": Int(asset.playbackStyle.rawValue),
            "subtypes": Self.subtypeNames(asset),
            "width": asset.pixelWidth,
            "height": asset.pixelHeight,
            "duration": asset.duration,
            "created": asset.creationDate?.timeIntervalSince1970 ?? 0,
            "modified": asset.modificationDate?.timeIntervalSince1970 ?? 0,
            "favorite": asset.isFavorite,
            "hidden": asset.isHidden,
            "hasAdjustments": asset.hasAdjustments,
            "sourceType": Int(asset.sourceType.rawValue),
            "sourceName": Self.sourceTypeName(asset),
            "burstIdentifier": asset.burstIdentifier ?? "",
            "latitude": asset.location?.coordinate.latitude ?? 0,
            "longitude": asset.location?.coordinate.longitude ?? 0,
            "hasLocation": asset.location != nil,
            "placeName": "",
            "albums": albums,
            "resources": rows,
            "resourceBytes": resourceBytes,
            "bytes": max(resourceBytes, cachedBytes),
            "sizeSource": (cached?["s"] as? String) ?? "",
            "error": "",
        ]

        guard let location = asset.location else {
            result(info)
            return
        }

        // 反查地名是网络请求，可能很久或直接失败；失败就留空，绝不让详情页卡住
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            var place = ""
            if let mark = placemarks?.first {
                let parts = [mark.name, mark.locality, mark.administrativeArea, mark.country]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                place = parts.joined(separator: " ")
            }
            DispatchQueue.main.async {
                info["placeName"] = place
                result(info)
            }
        }
    }

    private static func resourceTypeName(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "audio"
        case .alternatePhoto: return "alternatePhoto"
        case .fullSizePhoto: return "fullSizePhoto"
        case .fullSizeVideo: return "fullSizeVideo"
        case .adjustmentData: return "adjustmentData"
        case .adjustmentBasePhoto: return "adjustmentBasePhoto"
        case .pairedVideo: return "pairedVideo"
        case .fullSizePairedVideo: return "fullSizePairedVideo"
        case .adjustmentBasePairedVideo: return "adjustmentBasePairedVideo"
        default: return "type(\(type.rawValue))"
        }
    }

    private static func subtypeNames(_ asset: PHAsset) -> [String] {
        let subtypes = asset.mediaSubtypes
        var names: [String] = []
        if subtypes.contains(.photoLive) { names.append("实况照片") }
        if subtypes.contains(.photoHDR) { names.append("HDR") }
        if subtypes.contains(.photoPanorama) { names.append("全景") }
        if subtypes.contains(.photoScreenshot) { names.append("截屏") }
        if subtypes.contains(.videoHighFrameRate) { names.append("慢动作") }
        if subtypes.contains(.videoTimelapse) { names.append("延时摄影") }
        return names
    }

    private static func sourceTypeName(_ asset: PHAsset) -> String {
        let raw = asset.sourceType.rawValue
        var parts: [String] = []
        if raw & 1 != 0 { parts.append("用户相册") }
        if raw & 2 != 0 { parts.append("iCloud 共享") }
        if raw & 4 != 0 { parts.append("iTunes 同步") }
        return parts.isEmpty ? "未知" : parts.joined(separator: "、")
    }

    // MARK: - 修改与删除

    private func setFlag(call: FlutterMethodCall, result: @escaping FlutterResult, favorite: Bool) {
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let value = args["value"] as? Bool,
              let asset = asset(for: id) else {
            result(["ok": false, "error": "参数不完整"])
            return
        }
        PHPhotoLibrary.shared().performChanges({
            // 这个 SDK 里 init(for:) 不是可失败初始化，别写成 guard let
            let change = PHAssetChangeRequest(for: asset)
            if favorite {
                change.isFavorite = value
            } else {
                change.isHidden = value
            }
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                result(["ok": success, "error": error?.localizedDescription ?? ""])
            }
        })
    }

    /// 删除资产 —— 与系统相册一致：进「最近删除」，30 天后系统自动清理。
    ///
    /// 需要显式 `confirm=true`：这是唯一会改动用户相册的入口，口子做窄。
    private func deleteAssets(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              args["confirm"] as? Bool == true else {
            result(["deleted": 0, "failed": 0, "error": "必须显式确认（confirm=true）"])
            return
        }
        let ids = args["ids"] as? [String] ?? []
        guard !ids.isEmpty else {
            result(["deleted": 0, "failed": 0, "error": "没有要删除的项目"])
            return
        }
        guard hasReadAccess() else {
            result(["deleted": 0, "failed": 0, "error": "没有相册访问权限"])
            return
        }

        var targets: [PHAsset] = []
        var missing = 0
        for id in ids {
            if let asset = asset(for: id) {
                targets.append(asset)
            } else {
                missing += 1
            }
        }
        guard !targets.isEmpty else {
            result(["deleted": 0, "failed": missing, "error": "要删除的项目已不在相册中"])
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(targets as NSArray)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    self.forgetAssets(ids)
                    result([
                        "deleted": targets.count,
                        "failed": missing,
                        "error": "",
                    ])
                } else {
                    result([
                        "deleted": 0,
                        "failed": ids.count,
                        "error": error?.localizedDescription ?? "删除失败",
                    ])
                }
            }
        })
    }

    /// 删掉之后把缓存里的记录一并清掉，否则重新扫描会把它们当成「大小未知」
    private func forgetAssets(_ ids: [String]) {
        workQueue.async {
            self.assetLock.lock()
            for id in ids {
                self.assets.removeValue(forKey: id)
            }
            self.assetLock.unlock()
            for id in ids {
                self.removeCachedEntry(id)
            }
            self.cacheDirty = true
            self.saveSizeCacheIfNeeded(force: true)
        }
    }

    // MARK: - 资产表与大小缓存

    private func storeAssets(_ map: [String: PHAsset]) {
        assetLock.lock()
        assets = map
        assetLock.unlock()
    }

    private func asset(for id: String) -> PHAsset? {
        assetLock.lock()
        let cached = assets[id]
        assetLock.unlock()
        if let cached = cached { return cached }
        // 冷启动时字典可能是空的（还没 loadAssets），退化成一次按 ID 查询
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private var cacheFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("photo_size_cache.json")
    }

    private func cachedEntry(_ id: String) -> [String: Any]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return sizeCache[id]
    }

    private func setCachedEntry(_ id: String, _ row: [String: Any]) {
        cacheLock.lock()
        sizeCache[id] = row
        cacheLock.unlock()
    }

    private func removeCachedEntry(_ id: String) {
        cacheLock.lock()
        sizeCache.removeValue(forKey: id)
        cacheLock.unlock()
    }

    private func loadSizeCache() {
        guard let data = try? Data(contentsOf: cacheFileURL) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return }
        guard let raw = object as? [String: Any] else { return }

        var parsed: [String: [String: Any]] = [:]
        parsed.reserveCapacity(raw.count)
        for (key, value) in raw {
            if let row = value as? [String: Any] {
                parsed[key] = row
            }
        }
        cacheLock.lock()
        sizeCache = parsed
        cacheLock.unlock()
    }

    private func saveSizeCacheIfNeeded(force: Bool) {
        guard cacheDirty else { return }
        if !force && unsavedRecords < 2000 { return }
        cacheDirty = false
        unsavedRecords = 0

        cacheLock.lock()
        let snapshot = sizeCache
        cacheLock.unlock()

        guard let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }
}
