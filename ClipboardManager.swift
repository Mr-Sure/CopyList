import SwiftUI
import AppKit

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

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var timer: Timer?
    private var backupTimer: Timer?
    private var lastChangeCount: Int
    private let storageURL: URL
    private let imagesDirectory: URL
    private let thumbnailsDirectory: URL
    private let backupDirectory: URL
    private var imageCache: [String: NSImage] = [:]
    private let maxCacheSize = 15
    
    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("ClipboardHistory")
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        storageURL = appDirectory.appendingPathComponent("history.json")
        imagesDirectory = appDirectory.appendingPathComponent("images")
        thumbnailsDirectory = appDirectory.appendingPathComponent("thumbnails")
        backupDirectory = appDirectory.appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        
        loadHistory()
        startMonitoring()
        startBackupTimer()
    }
    
    func startMonitoring() {
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
        
        // 每 30 秒清理一次图片缓存，防止内存泄漏
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.imageCache.removeAll()
        }
    }
    
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            // 保存原图
            if let imageData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: imageData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let filename = "\(UUID().uuidString).png"
                let fileURL = imagesDirectory.appendingPathComponent(filename)
                try? pngData.write(to: fileURL)
                
                // 生成缩略图
                _ = generateThumbnail(for: image, filename: filename)
                
                addItem(ClipboardItem(type: .image, content: filename))
            }
        } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            // 检查是否为图片文件
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "webp"]
            if urls.count == 1, imageExtensions.contains(urls[0].pathExtension.lowercased()) {
                // 单个图片文件：保存为图片类型
                if let image = NSImage(contentsOf: urls[0]),
                   let imageData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: imageData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    let filename = "\(UUID().uuidString).png"
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    try? pngData.write(to: fileURL)
                    
                    // 生成缩略图
                    _ = generateThumbnail(for: image, filename: filename)
                    
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
                    NSLog("CopyList: 跳过图片文件名: %@", string)
                    return
                }
            }
            
            let newItem = ClipboardItem(type: .text, content: string)
            addItem(newItem)
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.content == item.content && $0.type == item.type }) {
            // 内容已存在：更新时间戳并移到顶部
            NSLog("CopyList: 检测到重复内容，从位置 %d 移到顶部", index + 1)
            var existingItem = items[index]
            existingItem.timestamp = Date()
            items.remove(at: index)
            items.insert(existingItem, at: 0)
            saveHistory()
            return
        }
        NSLog("CopyList: 添加新内容，类型: %@", String(describing: item.type))
        items.insert(item, at: 0)
        if items.count > 1000 {
            items = Array(items.prefix(1000))
        }
        saveHistory()
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .image:
            let fileURL = imagesDirectory.appendingPathComponent(item.content)
            if let image = NSImage(contentsOf: fileURL) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let paths = item.content.components(separatedBy: "\n")
            let urls = paths.compactMap { URL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls as [NSPasteboardWriting])
        }
        
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.copyCount += 1
            
            if updatedItem.copyCount >= 10 {
                updatedItem.isFavorite = true
            }
            
            items.remove(at: index)
            items.insert(updatedItem, at: 0)
            saveHistory()
        }
        
        lastChangeCount = pasteboard.changeCount
    }
    
    func deleteItem(_ item: ClipboardItem) {
        if item.type == .image {
            let fileURL = imagesDirectory.appendingPathComponent(item.content)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isFavorite.toggle()
            saveHistory()
        }
    }
    
    func addTag(_ item: ClipboardItem, tag: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            if !items[index].tags.contains(tag) {
                items[index].tags.append(tag)
                saveHistory()
            }
        }
    }
    
    func removeTag(_ item: ClipboardItem, tag: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].tags.removeAll { $0 == tag }
            saveHistory()
        }
    }
    
    func updateItem(_ item: ClipboardItem, newContent: String) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].content = newContent
            saveHistory()
        }
    }
    
    func clearAll() {
        for item in items where item.type == .image && !item.isFavorite {
            let fileURL = imagesDirectory.appendingPathComponent(item.content)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { !$0.isFavorite }
        saveHistory()
    }
    
    func clearFavorites() {
        for item in items where item.type == .image && item.isFavorite {
            let fileURL = imagesDirectory.appendingPathComponent(item.content)
            try? FileManager.default.removeItem(at: fileURL)
        }
        items.removeAll { $0.isFavorite }
        saveHistory()
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: storageURL)
        }
    }
    
    private func loadHistory() {
        if let data = try? Data(contentsOf: storageURL),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
        }
    }
    
    func getImage(for filename: String) -> NSImage? {
        // 检查缓存
        if let cached = imageCache[filename] {
            return cached
        }
        
        // 优先加载缩略图
        let thumbURL = thumbnailsDirectory.appendingPathComponent(filename)
        if let thumbnail = NSImage(contentsOf: thumbURL) {
            if imageCache.count >= maxCacheSize {
                imageCache.removeAll()
            }
            imageCache[filename] = thumbnail
            return thumbnail
        }
        
        // 缩略图不存在，从原图生成
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        
        // 生成并保存缩略图
        let thumbnail = generateThumbnail(for: image, filename: filename)
        
        if imageCache.count >= maxCacheSize {
            imageCache.removeAll()
        }
        imageCache[filename] = thumbnail
        
        return thumbnail
    }
    
    private func generateThumbnail(for image: NSImage, filename: String) -> NSImage {
        let thumbSize: CGFloat = 48
        let imageSize = image.size
        let scale = min(thumbSize / imageSize.width, thumbSize / imageSize.height)
        let newSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: imageSize),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()
        
        // 保存缩略图
        if let tiffData = thumbnail.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let thumbURL = thumbnailsDirectory.appendingPathComponent(filename)
            try? pngData.write(to: thumbURL)
        }
        
        return thumbnail
    }
    
    private func startBackupTimer() {
        backupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.backupFavorites()
        }
    }
    
    private func backupFavorites() {
        let favorites = items.filter { $0.isFavorite }
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
        let favorites = items.filter { $0.isFavorite }
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
