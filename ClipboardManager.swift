import SwiftUI
import AppKit

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: String
    let type: ItemType
    var content: String
    var timestamp: Date
    var isFavorite: Bool
    var copyCount: Int
    
    enum ItemType: String, Codable {
        case text
        case image
        case file
    }
    
    init(id: String = UUID().uuidString, type: ItemType, content: String, timestamp: Date = Date(), isFavorite: Bool = false, copyCount: Int = 0) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.copyCount = copyCount
    }
}

class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    private var timer: Timer?
    private var lastChangeCount: Int
    private let storageURL: URL
    private let imagesDirectory: URL
    
    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("ClipboardHistory")
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        storageURL = appDirectory.appendingPathComponent("history.json")
        imagesDirectory = appDirectory.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        
        loadHistory()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            let pathString = urls.map { $0.path }.joined(separator: "\n")
            let newItem = ClipboardItem(type: .file, content: pathString)
            if !items.contains(where: { $0.content == newItem.content && $0.type == newItem.type }) {
                addItem(newItem)
            }
        } else if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage {
            if let imageData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: imageData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let filename = "\(UUID().uuidString).png"
                let fileURL = imagesDirectory.appendingPathComponent(filename)
                try? pngData.write(to: fileURL)
                addItem(ClipboardItem(type: .image, content: filename))
            }
        } else if let string = pasteboard.string(forType: .string), !string.isEmpty {
            let newItem = ClipboardItem(type: .text, content: string)
            if !items.contains(where: { $0.content == newItem.content && $0.type == newItem.type }) {
                addItem(newItem)
            }
        }
    }
    
    func addItem(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.content == item.content && $0.type == item.type }) {
            var existingItem = items[index]
            existingItem.timestamp = Date()
            items[index] = existingItem
            saveHistory()
            return
        }
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
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }
}
