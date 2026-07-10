import SwiftUI
import AppKit
import ImageIO
import os.log

/// 统一日志:type: .debug 在 Release 默认不落盘,近乎零开销
private let clLogger = OSLog(subsystem: "com.copylist.app", category: "clipboard")
@inline(__always)
private func clLog(_ message: StaticString, _ args: CVarArg...) {
    os_log(message, log: clLogger, type: .debug, args)
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: String
    let type: ItemType
    var content: String
    var timestamp: Date
    var isFavorite: Bool
    var copyCount: Int
    var tags: [String]
    
    enum ItemType: String, Codable {
        case text
        case image
        case file
    }
    
    init(id: String = UUID().uuidString, type: ItemType, content: String, timestamp: Date = Date(), isFavorite: Bool = false, copyCount: Int = 0, tags: [String] = []) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.copyCount = copyCount
        self.tags = tags
    }
}

enum TagSaveResult {
    case saved
    case empty
    case duplicate
    case failed

    var message: String? {
        switch self {
        case .saved: return nil
        case .empty: return "请输入标签名称"
        case .duplicate: return "该标签已存在"
        case .failed: return "标签保存失败，请重试"
        }
    }
}

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published private(set) var totalItemCount = 0
    @Published private(set) var favoriteItemCount = 0
    @Published private(set) var availableTags: [String] = []
    private var timer: Timer?
    private var backupTimer: Timer?
    /// 定期清理未使用的图片缓存（每 5 分钟）
    private var cacheCleanupTimer: Timer?
    private var lastChangeCount: Int
    private let legacyStorageURL: URL
    private let store: ClipboardStore
    private let imagesDirectory: URL
    private let thumbnailsDirectory: URL
    private let backupDirectory: URL
    private let pageSize = 100
    private var activeQuery = ClipboardStore.Query()
    private var hasLoadedAllPages = false
    private var isLoadingPage = false
    /// 内存压力监听源(macOS 上等价于 didReceiveMemoryWarningNotification)
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB,按字节 LRU 淘汰
        return cache
    }()
    
    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("ClipboardHistory")
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        legacyStorageURL = appDirectory.appendingPathComponent("history.json")
        imagesDirectory = appDirectory.appendingPathComponent("images")
        thumbnailsDirectory = appDirectory.appendingPathComponent("thumbnails")
        backupDirectory = appDirectory.appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        store = try! ClipboardStore(databaseURL: appDirectory.appendingPathComponent("history.sqlite"))
        
        migrateLegacyHistoryIfNeeded()
        resetLoadedPage()
        startMonitoring()
        startBackupTimer()
        registerMemoryWarning()
        startCacheCleanupTimer()
    }
    
    deinit {
        memoryPressureSource?.cancel()
        timer?.invalidate()
        backupTimer?.invalidate()
        cacheCleanupTimer?.invalidate()
    }
    
    /// 系统内存压力(.warning/.critical)时清空图片缓存
    /// (NSCache 自身也会响应压力,这里做显式兜底)
    private func registerMemoryWarning() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.imageCache.removeAllObjects()
            clLog("CopyList: 收到内存压力事件,已清空图片缓存")
        }
        source.resume()
        memoryPressureSource = source
    }
    
    func startMonitoring() {
        // 已在运行则不重复启动
        guard timer == nil else { return }
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    /// popover 关闭时调用,停止后台轮询以降低 idle CPU
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    /// SQLite 每次变更均已提交；保留此接口以兼容应用生命周期调用。
    func flushPendingSave() {
    }
    
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            // 用 autoreleasepool 限制临时 NSImage / 位图的作用域，写盘后立即释放
            autoreleasepool {
                // 保存原图
                guard let imageData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: imageData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
                let filename = "\(UUID().uuidString).png"
                let fileURL = imagesDirectory.appendingPathComponent(filename)
                try? pngData.write(to: fileURL)

                // 缩略图改为从已落盘的原图流式生成，不再持有内存中的全尺寸 NSImage
                _ = generateThumbnailFromFile(at: fileURL, filename: filename)

                addItem(ClipboardItem(type: .image, content: filename))
            }
        } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            // 检查是否为图片文件
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
            if urls.count == 1, imageExtensions.contains(urls[0].pathExtension.lowercased()) {
                // 单个图片文件：保存为图片类型（需转码为统一 PNG，必须解码原图）
                autoreleasepool {
                    guard let image = NSImage(contentsOf: urls[0]),
                          let imageData = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: imageData),
                          let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
                    let filename = "\(UUID().uuidString).png"
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    try? pngData.write(to: fileURL)

                    // 缩略图从已落盘的原图流式生成
                    _ = generateThumbnailFromFile(at: fileURL, filename: filename)

                    addItem(ClipboardItem(type: .image, content: filename))
                }
            } else {
                // 其他文件：保存为文件类型
                let pathString = urls.map { $0.path }.joined(separator: "\n")
                let newItem = ClipboardItem(type: .file, content: pathString)
                addItem(newItem)
            }
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            // 跳过 UUID 格式的图片文件名（防止自己复制的图片被当作文本保存）
            if string.hasSuffix(".png") && string.count == 40 {
                // 格式类似：CA218F0E-1649-43BB-9C53-747C29F674E6.png
                let nameWithoutExt = string.dropLast(4) // 去掉 .png
                if nameWithoutExt.contains("-") && nameWithoutExt.filter({ $0 == "-" }).count == 4 {
                    clLog("CopyList: 跳过图片文件名: %s", string)
                    return
                }
            }
            
            let newItem = ClipboardItem(type: .text, content: string)
            addItem(newItem)
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        do {
            if var existingItem = try store.duplicate(type: item.type, content: item.content) {
                existingItem.timestamp = Date()
                try store.update(existingItem)
            } else {
                try store.insert(item)
            }
            resetLoadedPage()
        } catch {
            clLog("CopyList: 保存记录失败")
        }
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .image:
            let fileURL = imagesDirectory.appendingPathComponent(item.content)
            // autoreleasepool 包裹全尺寸解码峰值,粘贴后立即释放位图
            autoreleasepool {
                if let image = NSImage(contentsOf: fileURL) {
                    pasteboard.writeObjects([image])
                }
            }
        case .file:
            let paths = item.content.components(separatedBy: "\n")
            let urls = paths.compactMap { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
        }
        
        do {
            var updatedItem = item
            updatedItem.copyCount += 1
            if updatedItem.copyCount >= 10 {
                updatedItem.isFavorite = true
            }
            updatedItem.timestamp = Date()
            try store.update(updatedItem)
            resetLoadedPage()
        } catch {
            clLog("CopyList: 更新记录失败")
        }
        
        lastChangeCount = pasteboard.changeCount
    }
    
    func deleteItem(_ item: ClipboardItem) {
        do {
            try store.delete(id: item.id)
            removeImageAssets(for: item)
            resetLoadedPage()
        } catch {
            clLog("CopyList: 删除记录失败")
        }
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        var updated = item; updated.isFavorite.toggle()
        persist(updated)
    }
    
    @discardableResult
    func addTag(_ item: ClipboardItem, tag: String) -> TagSaveResult {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return .empty }
        guard !item.tags.contains(where: { $0.caseInsensitiveCompare(normalizedTag) == .orderedSame }) else {
            return .duplicate
        }

        var updated = item
        updated.tags.append(normalizedTag)
        do {
            try store.update(updated)
            resetLoadedPage()
            return .saved
        } catch {
            clLog("CopyList: 标签保存失败")
            return .failed
        }
    }
    
    func removeTag(_ item: ClipboardItem, tag: String) {
        var updated = item; updated.tags.removeAll { $0 == tag }
        persist(updated)
    }
    
    func updateItem(_ item: ClipboardItem, newContent: String) {
        var updated = item; updated.content = newContent
        persist(updated)
    }
    
    func clearAll() {
        do {
            try store.imageFilenames(favorites: false).forEach(removeImageAssets)
            try store.deleteAll(favorites: false)
            resetLoadedPage()
        } catch {
            clLog("CopyList: 清空历史失败")
        }
    }
    
    func clearFavorites() {
        do {
            try store.imageFilenames(favorites: true).forEach(removeImageAssets)
            try store.deleteAll(favorites: true)
            resetLoadedPage()
        } catch {
            clLog("CopyList: 清空收藏失败")
        }
    }

    /// 更新当前列表的数据库查询；只保留首个分页在内存中。
    func configureQuery(favoritesOnly: Bool, tag: String?, searchText: String) {
        let query = ClipboardStore.Query(favoritesOnly: favoritesOnly, tag: tag,
                                         searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard query != activeQuery else { return }
        activeQuery = query
        resetLoadedPage()
    }

    /// 末行出现时由 UI 调用，逐页追加而不是加载全部历史。
    func loadNextPage() {
        guard !isLoadingPage, !hasLoadedAllPages else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try store.page(for: activeQuery, offset: items.count, limit: pageSize)
            items.append(contentsOf: page)
            hasLoadedAllPages = page.count < pageSize
        } catch {
            clLog("CopyList: 读取历史失败")
        }
    }

    private func resetLoadedPage() {
        items = []
        hasLoadedAllPages = false
        refreshCounts()
        loadNextPage()
    }

    private func refreshCounts() {
        do {
            totalItemCount = try store.count(activeQuery)
            favoriteItemCount = try store.favoriteCount()
            availableTags = try store.favoriteTags()
        } catch {
            clLog("CopyList: 刷新统计失败")
        }
    }

    private func persist(_ item: ClipboardItem) {
        do {
            try store.update(item)
            resetLoadedPage()
        } catch {
            clLog("CopyList: 保存修改失败")
        }
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard (try? store.isEmpty()) == true,
              let data = try? Data(contentsOf: legacyStorageURL),
              let legacyItems = try? JSONDecoder().decode([ClipboardItem].self, from: data),
              !legacyItems.isEmpty else { return }
        do {
            try store.importLegacy(legacyItems)
            let migratedURL = legacyStorageURL.appendingPathExtension("migrated")
            if FileManager.default.fileExists(atPath: migratedURL.path) {
                try FileManager.default.removeItem(at: migratedURL)
            }
            try FileManager.default.moveItem(at: legacyStorageURL, to: migratedURL)
        } catch {
            clLog("CopyList: 迁移旧历史失败")
        }
    }

    private func removeImageAssets(for item: ClipboardItem) {
        guard item.type == .image else { return }
        removeImageAssets(item.content)
    }

    private func removeImageAssets(_ filename: String) {
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(filename))
        try? FileManager.default.removeItem(at: thumbnailsDirectory.appendingPathComponent(filename))
        imageCache.removeObject(forKey: filename as NSString)
    }
    
    func getImage(for filename: String) -> NSImage? {
        // 检查 NSCache（自动 LRU 淘汰，响应内存警告）
        if let cached = imageCache.object(forKey: filename as NSString) {
            return cached
        }

        // 优先加载已落盘的缩略图（小文件，占用低）
        let thumbURL = thumbnailsDirectory.appendingPathComponent(filename)
        if let thumbnail = NSImage(contentsOf: thumbURL) {
            cacheImage(thumbnail, for: filename)
            return thumbnail
        }

        // 缩略图不存在：用 ImageIO 从原图流式生成（绝不全尺寸解码原图）
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard let thumbnail = generateThumbnailFromFile(at: fileURL, filename: filename) else {
            return nil
        }
        cacheImage(thumbnail, for: filename)
        return thumbnail
    }
    
    /// 仅查缓存,不触发任何磁盘 I/O。供 UI 决定走同步还是异步路径。
    func getCachedImage(for filename: String) -> NSImage? {
        return imageCache.object(forKey: filename as NSString)
    }
    
    /// 缓存图片并按估算字节设置 cost(供 NSCache 按字节 LRU 淘汰)
    private func cacheImage(_ image: NSImage, for filename: String) {
        let rep = image.representations.first
        let pixels = (rep?.pixelsWide ?? 96) * (rep?.pixelsHigh ?? 96)
        let cost = pixels * 4 // RGBA 每像素 4 字节
        imageCache.setObject(image, forKey: filename as NSString, cost: cost)
    }

    /// 通过 ImageIO 的 CGImageSourceCreateThumbnailAtIndex 从文件流式生成缩略图，
    /// 不把原图全尺寸解码到内存，避免大图解码峰值（单张 1MB PNG 解码后可达数十 MB 位图）。
    /// 顺带用 96px（48pt @2x）解决原 48px 在 Retina 屏模糊的问题。
    private func generateThumbnailFromFile(at fileURL: URL, filename: String) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let maxPixel: CGFloat = 96 // 48pt @2x
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        // 保存缩略图到磁盘，下次直接读取小文件
        if let tiffData = thumbnail.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let thumbURL = thumbnailsDirectory.appendingPathComponent(filename)
            try? pngData.write(to: thumbURL)
        }

        return thumbnail
    }
    
    /// 定期清空图片缓存，防止长期运行时缓存无限增长
    private func startCacheCleanupTimer() {
        cacheCleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.imageCache.removeAllObjects()
            clLog("CopyList: 定期清理图片缓存")
        }
    }
    
    private func startBackupTimer() {
        backupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.backupFavorites()
        }
    }
    
    private func backupFavorites() {
        let favorites = (try? store.allFavorites()) ?? []
        if favorites.isEmpty { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupURL = backupDirectory.appendingPathComponent("favorites_\(timestamp).json")
        
        if let data = try? JSONEncoder().encode(favorites) {
            try? data.write(to: backupURL)
        }
        
        cleanOldBackups()
    }
    
    private func cleanOldBackups() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        let backupFiles = files.filter { $0.pathExtension == "json" }
            .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast) ?? Date.distantPast >
                     (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast) ?? Date.distantPast }
        
        if backupFiles.count > 10 {
            for file in backupFiles.dropFirst(10) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    func exportFavorites() -> URL? {
        let favorites = (try? store.allFavorites()) ?? []
        guard !favorites.isEmpty else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("CopyList_收藏夹_\(timestamp).json")
        
        if let data = try? JSONEncoder().encode(favorites) {
            try? data.write(to: exportURL)
            return exportURL
        }
        return nil
    }
}
