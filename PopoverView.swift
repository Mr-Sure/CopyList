import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @AppStorage("enableAutopaste") private var enableAutopaste = true
    @State private var searchText = ""
    @State private var isEditMode = false
    @State private var editingItem: ClipboardItem?
    @State private var editText = ""
    @State private var hasUpdate = false
    @State private var latestVersion = ""
    @State private var showCopiedIndex: Int? = nil
    @State private var showFavorites = false
    @State private var showClearAlert = false
    @State private var showSettings = false
    @State private var allowPasteThisTime = true
    @State private var selectedTag: String? = nil
    @State private var showTagInput: ClipboardItem? = nil
    @State private var newTag = ""
    
    var allTags: [String] {
        Array(Set(clipboardManager.items.flatMap { $0.tags })).sorted()
    }
    
    var filteredItems: [ClipboardItem] {
        var baseItems = showFavorites 
            ? clipboardManager.items.filter { $0.isFavorite }.sorted { $0.copyCount > $1.copyCount }
            : clipboardManager.items
        
        if let tag = selectedTag {
            baseItems = baseItems.filter { $0.tags.contains(tag) }
        }
        
        if searchText.isEmpty {
            return baseItems
        }
        return baseItems.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
    }
    
    var favoriteCount: Int {
        clipboardManager.items.filter { $0.isFavorite }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("搜索历史...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focusable(false)
                    .onTapGesture {
                        allowPasteThisTime = false
                    }
                    .onChange(of: searchText) { _ in
                        allowPasteThisTime = false
                    }
                
                if !searchText.isEmpty {
                    Button(action: { 
                        searchText = ""
                        allowPasteThisTime = true
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
                        if let url = URL(string: "https://github.com/yourusername/copylist/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
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
                    VStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ItemRow(
                                item: item,
                                index: index + 1,
                                isEditMode: isEditMode,
                                shouldPaste: enableAutopaste && allowPasteThisTime,
                                showCopiedState: $showCopiedIndex,
                                showTagInput: $showTagInput,
                                onEdit: {
                                    editingItem = item
                                    editText = item.content
                                }
                            )
                            Divider()
                        }
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Text("共 \(clipboardManager.items.count) 条")
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
                        clipboardManager.updateItem(item, newContent: editText)
                        editingItem = nil
                        isEditMode = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
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
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                
                TextField("输入标签名称", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("取消") {
                        showTagInput = nil
                        newTag = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("添加") {
                        if !newTag.isEmpty {
                            clipboardManager.addTag(item, tag: newTag)
                            showTagInput = nil
                            newTag = ""
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newTag.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 320, height: 160)
        }
    }
    
    func checkForUpdates() {
        guard let url = URL(string: "https://raw.githubusercontent.com/yourusername/copylist/main/version.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = json["version"] as? String else { return }
            
             DispatchQueue.main.async {
                self.latestVersion = version
                if self.compareVersions("1.0.0", version) {
                    self.hasUpdate = true
                }
            }
        }
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
    let item: ClipboardItem
    let index: Int
    let isEditMode: Bool
    let shouldPaste: Bool
    @Binding var showCopiedState: Int?
    @Binding var showTagInput: ClipboardItem?
    let onEdit: () -> Void
    
    var showCopied: Bool {
        showCopiedState == index
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 24)
            
            if item.type == .image, let image = clipboardManager.getImage(for: item.content) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .onTapGesture {
                clipboardManager.toggleFavorite(item)
            }
            
            if isEditMode {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onTapGesture {
                    onEdit()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                NSLog("=== CopyList: 开始复制流程 ===")
                NSLog("CopyList: 项目索引 %d", index)
                NSLog("CopyList: 项目类型 %@", String(describing: item.type))
                NSLog("CopyList: 是否应该粘贴 %@", shouldPaste ? "是" : "否")
                
                clipboardManager.copyToClipboard(item)
                showCopiedState = index
                
                if shouldPaste {
                    NSLog("CopyList: 准备自动粘贴...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        showCopiedState = nil
                        NSLog("CopyList: 关闭 Popover")
                        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NSLog("CopyList: 开始执行粘贴操作")
                            
                            // 检查辅助功能权限
                            let trusted = AXIsProcessTrusted()
                            NSLog("CopyList: 辅助功能权限状态 %@", trusted ? "✅已授权" : "❌未授权")
                            
                            if !trusted {
                                NSLog("CopyList: ❌ 没有辅助功能权限，无法自动粘贴")
                                return
                            }
                            
                            // 使用 AppleScript
                            // 注意：如果用户交换了 Command 和 Control 键，这里会自动适应系统设置
                            let script = NSAppleScript(source: """
                            tell application "System Events"
                                delay 0.1
                                key code 9 using command down
                            end tell
                            """)
                            
                            var errorDict: NSDictionary?
                            _ = script?.executeAndReturnError(&errorDict)
                            
                            if let error = errorDict {
                                NSLog("CopyList: ❌ AppleScript 执行失败: %@", error)
                            } else {
                                NSLog("CopyList: ✅ AppleScript 执行成功")
                            }
                            
                            NSLog("CopyList: === 粘贴流程完成 ===")
                        }
                    }
                } else {
                    NSLog("CopyList: 自动粘贴已关闭，仅复制到剪贴板")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showCopiedState = nil
                    }
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
            if item.isFavorite {
                Button(action: { showTagInput = item }) {
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
            }
            
            Button(role: .destructive, action: { clipboardManager.deleteItem(item) }) {
                Label("删除", systemImage: "trash")
            }
        }
    }
    
    var previewText: String {
        switch item.type {
        case .text:
            return item.content
        case .image:
            return "图片"
        case .file:
            let paths = item.content.components(separatedBy: "\n")
            return paths.count > 1 ? "\(paths.count) 个文件" : paths.first?.components(separatedBy: "/").last ?? "文件"
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
