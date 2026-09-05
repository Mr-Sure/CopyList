import SwiftUI
import AppKit
import os.log

private let popoverLogger = OSLog(subsystem: "com.copylist.app", category: "popover")
@inline(__always)
private func pLog(_ message: StaticString, _ args: CVarArg...) {
    os_log(message, log: popoverLogger, type: .debug, args)
}

struct PopoverView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var hasUpdate = false
    @State private var latestVersion = ""
    @State private var lastUpdateCheckAt = Date.distantPast
    /// 用条目 id（而非行号）标记“已复制”，避免列表重排后 ✓ 显示在错误的行上
    @State private var showCopiedItemID: String? = nil
    @State private var showFavorites = false
    @State private var searchText = ""
    @State private var isEditMode = false
    @State private var editingItem: ClipboardItem?
    @State private var editText = ""
    @State private var showClearAlert = false
    @State private var showSettings = false
    @State private var selectedTag: String? = nil
    @State private var showTagInput: ClipboardItem? = nil
    @State private var newTag = ""
    @State private var tagSaveMessage: String? = nil
    /// 自动粘贴因缺少系统权限失败时显示一次性提示
    @State private var pasteFailedNotice: String? = nil
    @FocusState private var isTagFieldFocused: Bool
    
    var allTags: [String] {
        clipboardManager.availableTags
    }
    
    var filteredItems: [ClipboardItem] {
        clipboardManager.items
    }
    
    var favoriteCount: Int {
        clipboardManager.favoriteItemCount
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("搜索历史...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focusable(false)
                
                if !searchText.isEmpty {
                    Button(action: { 
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: { isEditMode.toggle() }) {
                    Image(systemName: isEditMode ? "pencil.circle.fill" : "pencil.circle")
                        .foregroundColor(isEditMode ? .blue : .gray)
                }
                .buttonStyle(.plain)
                .help(isEditMode ? "退出编辑模式" : "进入编辑模式")
            }
            .padding(12)
            .background(Color.gray.opacity(0.05))
            
            HStack {
                Image(systemName: showFavorites ? "star.fill" : "star")
                    .foregroundColor(.orange)
                Text(showFavorites ? "全部历史" : "收藏夹")
                    .font(.subheadline)
                Spacer()
                Text("\(favoriteCount)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(showFavorites ? Color.orange.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                showFavorites.toggle()
            }
            
            if showFavorites && !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(action: { selectedTag = nil }) {
                            Text("全部")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedTag == nil ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedTag == nil ? .white : .primary)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        ForEach(allTags, id: \.self) { tag in
                            Button(action: { selectedTag = tag }) {
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTag == tag ? Color.blue : Color.gray.opacity(0.2))
                                    .foregroundColor(selectedTag == tag ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color.gray.opacity(0.05))
            }
            
            if hasUpdate {
                HStack {
                    Text("发现新版本 \(latestVersion)")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Spacer()
                    Button("更新") {
                        if let url = URL(string: "https://github.com/Mr-Sure/CopyList/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)

                    Button(action: { hasUpdate = false }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("暂不提醒")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
            }

            if let pasteFailedNotice {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(pasteFailedNotice)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button(action: { self.pasteFailedNotice = nil }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }
            
            Divider()
            
            if filteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text(searchText.isEmpty ? "暂无历史记录" : "无搜索结果")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ItemRow(
                                item: item,
                                index: index + 1,
                                isEditMode: isEditMode,
                                showCopiedItemID: $showCopiedItemID,
                                showTagInput: $showTagInput,
                                newTag: $newTag,
                                tagSaveMessage: $tagSaveMessage,
                                onEdit: {
                                    editingItem = item
                                    editText = item.content
                                },
                                onSelect: {
                                    searchText = ""
                                    showFavorites = false
                                    selectedTag = nil
                                },
                                onPastePermissionDenied: {
                                    pasteFailedNotice = "自动粘贴失败：缺少辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能）"
                                },
                                onPasteScriptDenied: {
                                    pasteFailedNotice = "自动粘贴失败：未获得“控制 System Events”自动化权限，请在系统设置中允许"
                                }
                            )
                            .onAppear {
                                if item.id == filteredItems.last?.id {
                                    clipboardManager.loadNextPage()
                                }
                            }
                            Divider()
                        }
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Text("已加载 \(clipboardManager.items.count) / 共 \(clipboardManager.totalItemCount) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { showClearAlert = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("清空")
                .alert(showFavorites ? "确认清空收藏夹？" : "确认清空剪贴板历史？", isPresented: $showClearAlert) {
                    Button("取消", role: .cancel) { }
                    Button("清空", role: .destructive) {
                        if showFavorites {
                            clipboardManager.clearFavorites()
                        } else {
                            clipboardManager.clearAll()
                        }
                    }
                } message: {
                    Text(showFavorites ? "将清空所有收藏项，此操作不可恢复" : "将清空所有剪贴板历史（不含收藏），此操作不可恢复")
                }
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("设置")
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(clipboardManager)
                }
                
                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("退出")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 320, height: 600)
        .onAppear {
            checkForUpdates()
        }
        .sheet(item: $editingItem) { item in
            VStack(spacing: 0) {
                HStack {
                    Text("编辑内容")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: { editingItem = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                Divider()

                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .frame(height: 180)
                    .padding(12)

                Divider()

                HStack(spacing: 12) {
                    Button("取消") {
                        editingItem = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("保存") {
                        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        clipboardManager.updateItem(item, newContent: editText)
                        editingItem = nil
                        isEditMode = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .frame(width: 320, height: 280)
        }
        .sheet(item: $showTagInput) { item in
            VStack(spacing: 16) {
                HStack {
                    Text("添加标签")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: { 
                        showTagInput = nil
                        newTag = ""
                        tagSaveMessage = nil
                        isTagFieldFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                TextField("输入标签名称", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTagFieldFocused)
                    .onSubmit {
                        saveTag(for: item)
                    }

                if let tagSaveMessage {
                    Text(tagSaveMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack {
                    Button("取消") {
                        showTagInput = nil
                        newTag = ""
                        tagSaveMessage = nil
                        isTagFieldFocused = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("添加") {
                        saveTag(for: item)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320, height: 160)
            .contentShape(Rectangle())
            .onTapGesture {
                isTagFieldFocused = true
            }
            .onAppear {
                focusTagFieldSoon()
            }
        }
        .onAppear { refreshQuery() }
        .onChange(of: showFavorites) { _ in refreshQuery() }
        .onChange(of: selectedTag) { _ in refreshQuery() }
        .onChange(of: searchText) { _ in refreshQuery() }
        .onReceive(clipboardManager.$availableTags) { tags in
            // 当前筛选的标签已不存在（标签被移除/清空收藏）时自动退出筛选，
            // 避免列表被“隐形筛选”成空列表而用户无从得知原因
            if let tag = selectedTag, !tags.contains(tag) {
                selectedTag = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyListPopoverDidClose)) { _ in
            resetTransientState()
        }
    }

    /// Popover 关闭后复位临时界面状态，避免下次打开弹出残留面板或过期的复制提示
    private func resetTransientState() {
        showSettings = false
        editingItem = nil
        showTagInput = nil
        newTag = ""
        tagSaveMessage = nil
        isTagFieldFocused = false
        showClearAlert = false
        showCopiedItemID = nil
        pasteFailedNotice = nil
    }

    private func refreshQuery() {
        clipboardManager.configureQuery(favoritesOnly: showFavorites, tag: selectedTag, searchText: searchText)
    }

    private func focusTagFieldSoon() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            isTagFieldFocused = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isTagFieldFocused = true
        }
    }

    private func closeTagInput() {
        showTagInput = nil
        newTag = ""
        tagSaveMessage = nil
        isTagFieldFocused = false
    }

    private func saveTag(for item: ClipboardItem) {
        switch clipboardManager.addTag(item, tag: newTag) {
        case .saved:
            closeTagInput()
        case let result:
            tagSaveMessage = result.message
            focusTagFieldSoon()
        }
    }
    
    func checkForUpdates() {
        // 5 分钟内不重复请求，避免每次打开 Popover 都访问 GitHub
        guard Date().timeIntervalSince(lastUpdateCheckAt) > 300 else { return }
        lastUpdateCheckAt = Date()
        // 注意：本仓库分支为 master（与 SettingsView 一致），使用 main 会导致 404 静默失败
        guard let url = URL(string: "https://raw.githubusercontent.com/Mr-Sure/CopyList/master/version.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? String else { return }
            
             DispatchQueue.main.async {
                self.latestVersion = version
                if self.compareVersions(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0", version) {
                    self.hasUpdate = true
                }
            }
        }.resume()
    }
    
    func compareVersions(_ current: String, _ latest: String) -> Bool {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(currentParts.count, latestParts.count) {
            let c = i < currentParts.count ? currentParts[i] : 0
            let l = i < latestParts.count ? latestParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
}

struct ItemRow: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    /// 与 SettingsView 保持一致：默认关闭，避免“设置里显示关、实际却自动粘贴”
    @AppStorage("enableAutopaste") private var enableAutopaste = false
    let item: ClipboardItem
    let index: Int
    let isEditMode: Bool
    @Binding var showCopiedItemID: String?
    @Binding var showTagInput: ClipboardItem?
    @Binding var newTag: String
    @Binding var tagSaveMessage: String?
    let onEdit: () -> Void
    let onSelect: () -> Void
    let onPastePermissionDenied: () -> Void
    let onPasteScriptDenied: () -> Void
    /// 异步加载的缩略图;缓存命中时直接同步赋值
    @State private var loadedImage: NSImage?
    /// 缩略图加载失败（文件缺失等），显示占位并停止重试
    @State private var imageLoadFailed = false
    /// 延迟清除“已复制”标记的任务；新复制时取消旧任务
    @State private var copiedClearWorkItem: DispatchWorkItem? = nil

    var showCopied: Bool {
        showCopiedItemID == item.id
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 24)
            
            if item.type == .image, let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if item.type == .image {
                // 异步加载中的占位符 / 加载失败的兜底
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: imageLoadFailed ? "photo.badge.exclamationmark" : "photo")
                            .font(.caption)
                            .foregroundColor(.gray)
                    )
            } else {
                Image(systemName: iconName)
                    .font(.body)
                    .foregroundColor(iconColor)
                    .frame(width: 36, height: 36)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .lineLimit(2)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 6) {
                    Text(item.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    if item.copyCount > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("\(item.copyCount)次")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if !item.tags.isEmpty {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        ForEach(item.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
            
            Button(action: {
                clipboardManager.toggleFavorite(item)
            }) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundColor(item.isFavorite ? .orange : .gray)
                    .font(.body)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            
            if isEditMode && item.type == .text {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clear)
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                // 直接读取 AppStorage 的 enableAutopaste，确保搜索后点击结果也能正常粘贴+关闭
                let doPaste = enableAutopaste

                pLog("=== CopyList: 开始复制流程 ===")
                pLog("CopyList: 项目索引 %d", index)
                pLog("CopyList: 项目类型 %s", String(describing: item.type))
                pLog("CopyList: 是否应该粘贴 %s", doPaste ? "是" : "否")

                // 选中记录后重置搜索状态
                onSelect()
                clipboardManager.copyToClipboard(item)

                if doPaste {
                    pLog("CopyList: 准备自动粘贴...")
                    pLog("CopyList: 关闭 Popover")
                    NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        pLog("CopyList: 开始执行粘贴操作")

                        // 检查辅助功能权限
                        let trusted = AXIsProcessTrusted()
                        pLog("CopyList: 辅助功能权限状态 %s", trusted ? "✅已授权" : "❌未授权")

                        guard trusted else {
                            pLog("CopyList: ❌ 没有辅助功能权限，无法自动粘贴")
                            onPastePermissionDenied()
                            return
                        }

                        // 使用 AppleScript(每次新建实例,避免预编译脚本状态污染)
                        let script = NSAppleScript(source: """
                        tell application "System Events"
                            key code 9 using command down
                        end tell
                        """)

                        var errorDict: NSDictionary?
                        _ = script?.executeAndReturnError(&errorDict)

                        if let error = errorDict {
                            pLog("CopyList: ❌ AppleScript 执行失败: %@", error)
                            onPasteScriptDenied()
                        } else {
                            pLog("CopyList: ✅ AppleScript 执行成功")
                        }
                    }
                } else {
                    // 以条目 id 标记复制成功，避免列表重排后 ✓ 显示在错误的行
                    showCopiedItemID = item.id
                    copiedClearWorkItem?.cancel()
                    let clear = DispatchWorkItem { showCopiedItemID = nil }
                    copiedClearWorkItem = clear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: clear)
                }
            }
        }
        .overlay(
            Group {
                if showCopied {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.green.opacity(0.9))
                            .clipShape(Circle())
                            .padding(.trailing, 8)
                    }
                }
            }
        )
        .contextMenu {
            Button(action: {
                newTag = ""
                tagSaveMessage = nil
                DispatchQueue.main.async {
                    showTagInput = item
                }
            }) {
                Label("添加标签", systemImage: "tag")
            }
            if !item.tags.isEmpty {
                Menu("移除标签") {
                    ForEach(item.tags, id: \.self) { tag in
                        Button(tag) {
                            clipboardManager.removeTag(item, tag: tag)
                        }
                    }
                }
            }
            Divider()

            Button(role: .destructive, action: { clipboardManager.deleteItem(item) }) {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    var previewText: String {
        switch item.type {
        case .text:
            // 长文本截断,避免 Text 完整测量整段内容(超长文本会拖慢布局)
            return item.content.count > 200
                ? String(item.content.prefix(200)) + "…"
                : item.content
        case .image:
            return "图片"
        case .file:
            let paths = item.content.components(separatedBy: "\n")
            return paths.count > 1 ? "\(paths.count) 个文件" : paths.first?.components(separatedBy: "/").last ?? "文件"
        }
    }
    
    /// 缩略图加载:缓存命中同步返回,否则异步解码后回主线程赋值,
    /// 避免滚动时主线程被磁盘 I/O / ImageIO 解码阻塞
    private func loadThumbnailIfNeeded() {
        guard item.type == .image, loadedImage == nil, !imageLoadFailed else { return }
        let filename = item.content
        // 先同步查缓存(命中时直接展示,不进异步路径)
        if let cached = clipboardManager.getCachedImage(for: filename) {
            loadedImage = cached
            return
        }
        // 缓存未命中,后台解码
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.clipboardManager.getImage(for: filename)
            DispatchQueue.main.async {
                if image == nil {
                    // 文件缺失/解码失败：标记后不再反复触发加载
                    self.imageLoadFailed = true
                }
                self.loadedImage = image
            }
        }
    }
    
    var iconName: String {
        switch item.type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }
    
    var iconColor: Color {
        switch item.type {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }
}
