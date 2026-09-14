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
                    .monospacedDigit()
                    .lineLimit(1)
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
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
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
        clipboardManager.configureQuery(favoritesOnly: showFavorites, tag: selectedTag, type: nil, searchText: searchText)
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
    /// 标签区 hover 状态：hover 标签条时原地展开完整标签流，离开后延迟收回
    @State private var isTagAreaHovered = false
    /// 延迟收回展开标签区的任务；鼠标从标签条移入展开区时取消，避免闪烁
    @State private var tagCollapseWorkItem: DispatchWorkItem? = nil

    /// 行内最多直接展示的标签数，其余折叠为 +N 徽标
    private static let inlineTagLimit = 2
    /// 展开标签流最多完整展示的标签数，防止极端多标签把行撑得过高
    private static let expandedTagLimit = 9
    /// 行内标签最大宽度：约 4 个中文字，超出即截断。
    /// 行内一行还要放下时间戳、次数与 +N 徽标，单标签上限过大会把整行顶宽
    private static let inlineTagMaxWidth: CGFloat = 64
    /// 展开标签流中单个标签的最大宽度，超出截断后交给 FlowLayout 换行
    private static let expandedTagMaxWidth: CGFloat = 140

    var showCopied: Bool {
        showCopiedItemID == item.id
    }

    /// 是否处于“展开全部标签”状态（仅当标签数超过行内展示上限时才有展开意义）
    private var showsAllTags: Bool {
        isTagAreaHovered && item.tags.count > Self.inlineTagLimit
    }

    /// 序号列。
    /// 原实现固定 `.frame(width: 24)`，但历史上限为 1000 条、收藏数量不设上限，
    /// 序号到 3 位以上（如 1000）时 24pt 已放不下，数字会被截断成 “10…” 或溢出压到类型图标上。
    /// 现在按位数动态放宽列宽，并用等宽数字 + 缩放下限兜底，保证序号完整且不侵占图标区域。
    private var indexLabel: some View {
        Text("\(index)")
            .font(.caption)
            .monospacedDigit()
            .foregroundColor(.gray)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: Self.indexColumnWidth(for: index), alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 序号列宽：1~2 位保持 24pt，之后每多一位加 8pt（caption 等宽数字约 6pt + 余量）
    private static func indexColumnWidth(for index: Int) -> CGFloat {
        24 + CGFloat(max(0, String(index).count - 2)) * 8
    }

    /// 标签条与展开区共用：进入立即展开，离开延迟 0.25s 收回，
    /// 保证鼠标从标签条移入展开区的过程中不会先收起再展开而闪烁
    private func handleTagHover(_ hovering: Bool) {
        if hovering {
            tagCollapseWorkItem?.cancel()
            tagCollapseWorkItem = nil
            withAnimation(.easeInOut(duration: 0.15)) { isTagAreaHovered = true }
        } else {
            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.15)) { isTagAreaHovered = false }
            }
            tagCollapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            indexLabel
            
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
                    // 展开标签流时预览缩为 1 行，尽量抵消展开增加的行高
                    .lineLimit(showsAllTags ? 1 : 2)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(item.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .fixedSize()
                        // 空间不足时让标签先被压缩/截断，时间戳与次数保持完整
                        .layoutPriority(1)

                    if item.copyCount > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("\(item.copyCount)次")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .fixedSize()
                            .layoutPriority(1)
                    }

                    // 行内标签区：hover 时整体隐藏（改由下方展开流完整展示），避免两份标签重复
                    if !item.tags.isEmpty, !showsAllTags {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(spacing: 4) {
                            ForEach(item.tags.prefix(Self.inlineTagLimit), id: \.self) { tag in
                                // 截断型标签可被压缩：标签多/标签长时先截断自身，
                                // 而不是把整行顶宽后把序号与收藏按钮挤出可视区
                                TagChip(text: tag, truncates: true, maxWidth: Self.inlineTagMaxWidth)
                            }
                            if item.tags.count > Self.inlineTagLimit {
                                TagChip(text: "+\(item.tags.count - Self.inlineTagLimit)",
                                        truncates: false, isOverflowMarker: true)
                                    .layoutPriority(2)
                            }
                        }
                        .layoutPriority(0)
                    }
                }
                // hover 触发区固定在“时间戳行”整条上（展开时行内标签区会消失，
                // 不能把触发区绑在被隐藏的标签上，否则会展开/收回死循环）
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHover { handleTagHover($0) }

                if showsAllTags {
                    // 展开态：完整标签流替换行内标签区（预览文本已缩为 1 行）
                    FlowLayout(spacing: 4) {
                        ForEach(item.tags.prefix(Self.expandedTagLimit), id: \.self) { tag in
                            // 展开流同样限制单标签宽度并允许截断，超长标签不会横向溢出整行
                            TagChip(text: tag, truncates: true, maxWidth: Self.expandedTagMaxWidth)
                        }
                        if item.tags.count > Self.expandedTagLimit {
                            TagChip(text: "+\(item.tags.count - Self.expandedTagLimit)",
                                    truncates: false, isOverflowMarker: true)
                        }
                    }
                    .onHover { handleTagHover($0) }
                    .transition(.opacity)
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
        .onReceive(NotificationCenter.default.publisher(for: .copyListPopoverDidClose)) { _ in
            // Popover 关闭时复位标签展开状态，避免下次打开时行残留展开
            tagCollapseWorkItem?.cancel()
            isTagAreaHovered = false
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

// MARK: - 标签展示组件

/// 标签胶囊：普通标签单行截断并限制最大宽度，防止长标签挤爆行内空间；
/// "+N" 徽标不截断、使用中性灰配色以示区分
///
/// 注意修饰符顺序：原实现把 `fixedSize()` 放在 `frame(maxWidth:)` 之前，
/// 等于是「先声明按理想尺寸绘制、再限制最大宽度」，`maxWidth` 实际形同虚设 ——
/// 长标签仍按自身理想宽度绘制并溢出到相邻内容上（表现为内容被遮挡）。
/// 现在改为：先由 `maxWidth` 约束宽度让文本走尾部截断，再补背景；
/// 只有不截断的 “+N” 徽标才保留 `fixedSize()` 抗压缩，避免被挤成省略号。
struct TagChip: View {
    let text: String
    var truncates: Bool
    /// 截断型标签的最大宽度；nil 表示不额外限制（仅用于短徽标）
    var maxWidth: CGFloat? = nil
    var isOverflowMarker: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: truncates ? (maxWidth ?? 96) : maxWidth)
            .background(isOverflowMarker ? Color.gray.opacity(0.18) : Color.blue.opacity(0.2))
            .foregroundColor(isOverflowMarker ? .secondary : .blue)
            .cornerRadius(4)
            .fixedSize(horizontal: !truncates, vertical: false)
    }
}

/// 流式布局：子视图按行排列、超出容器宽度自动换行（macOS 13+ Layout 协议）。
/// 单个子视图比容器还宽时收敛到容器宽度（原实现只在“已有前序子视图”时换行，
/// 首个超宽子视图会直接横向溢出到界面外），并把收敛后的宽度作为提案交给子视图以触发截断。
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = clampedSize(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = clampedSize(of: subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// 理想尺寸，并把宽度收敛到容器宽度内（宽度不受限时不做裁剪）
    private func clampedSize(of subview: LayoutSubviews.Element, maxWidth: CGFloat) -> CGSize {
        var size = subview.sizeThatFits(.unspecified)
        if maxWidth.isFinite {
            size.width = min(size.width, maxWidth)
        }
        return size
    }
}
