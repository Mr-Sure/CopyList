import SwiftUI
import AppKit

struct MainWindowView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @State private var selectedItem: ClipboardItem?
    @State private var showingEditSheet = false
    @State private var filterType: ClipboardItem.ItemType?
    
    var filteredItems: [ClipboardItem] {
        var items = clipboardManager.items
        
        if let type = filterType {
            items = items.filter { $0.type == type }
        }
        
        if !searchText.isEmpty {
            items = items.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
        
        return items
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("搜索...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    Menu {
                        Button("全部") { filterType = nil }
                        Button("文本") { filterType = .text }
                        Button("图片") { filterType = .image }
                        Button("文件") { filterType = .file }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Button(action: { clipboardManager.clearAll() }) {
                        Image(systemName: "trash")
                    }
                }
                .padding()
                
                Divider()
                
                if filteredItems.isEmpty {
                    VStack {
                        Spacer()
                        Text("暂无历史记录")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List(filteredItems, selection: $selectedItem) { item in
                        ClipboardItemCell(item: item)
                            .tag(item)
                            .contextMenu {
                                Button("复制") {
                                    clipboardManager.copyToClipboard(item)
                                }
                                if item.type == .text {
                                    Button("编辑") {
                                        selectedItem = item
                                        showingEditSheet = true
                                    }
                                }
                                Button(item.isFavorite ? "取消收藏" : "收藏") {
                                    clipboardManager.toggleFavorite(item)
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    clipboardManager.deleteItem(item)
                                    if selectedItem?.id == item.id {
                                        selectedItem = nil
                                    }
                                }
                            }
                    }
                    .listStyle(.sidebar)
                }
            }
        } detail: {
            if let item = selectedItem {
                ClipboardDetailView(item: item)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("选择一个项目查看详情")
                        .font(.title3)
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let item = selectedItem {
                EditItemView(item: item)
            }
        }
    }
}

struct ClipboardItemCell: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    let item: ClipboardItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .lineLimit(2)
                    .font(.body)
                
                HStack {
                    Text(item.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
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

struct ClipboardDetailView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    let item: ClipboardItem
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预览")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    clipboardManager.copyToClipboard(item)
                }) {
                    Label("复制到剪贴板", systemImage: "doc.on.clipboard")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(typeText, systemImage: iconName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Text(item.timestamp, style: .date)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(item.timestamp, style: .time)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    switch item.type {
                    case .text:
                        Text(item.content)
                            .textSelection(.enabled)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                    case .image:
                        if let image = clipboardManager.getImage(for: item.content) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 600, maxHeight: 600)
                                .cornerRadius(8)
                        }
                        
                    case .file:
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(item.content.components(separatedBy: "\n"), id: \.self) { path in
                                HStack {
                                    Image(systemName: "doc")
                                        .foregroundColor(.blue)
                                    Text(path)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    var typeText: String {
        switch item.type {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
    
    var iconName: String {
        switch item.type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }
}

struct EditItemView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @Environment(\.dismiss) var dismiss
    let item: ClipboardItem
    @State private var editedContent: String
    
    init(item: ClipboardItem) {
        self.item = item
        _editedContent = State(initialValue: item.content)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("编辑内容")
                .font(.headline)
            
            TextEditor(text: $editedContent)
                .font(.body)
                .border(Color.gray.opacity(0.2))
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                Spacer()
                Button("保存") {
                    clipboardManager.updateItem(item, newContent: editedContent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}
