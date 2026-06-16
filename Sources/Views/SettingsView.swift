import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("enableAutopaste") private var enableAutopaste = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    /// 历史上限,与 ClipboardManager 共用同一个 key
    @AppStorage("maxHistoryItems") private var maxHistoryItems: Int = 1000
    @State private var showingClearAlert = false
    @State private var showUpdateAlert = false
    @State private var updateMessage = ""
    
    /// 从 Bundle 动态读取版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }
    /// 从 Bundle 动态读取构建时间
    private var buildTime: String {
        Bundle.main.infoDictionary?["CLBuildTime"] as? String ?? "未知"
    }
    
    private let limitOptions: [(label: String, value: Int)] = [
        ("200", 200), ("500", 500), ("1000", 1000), ("2000", 2000), ("5000", 5000)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("通用", systemImage: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 0) {
                            SettingRow {
                                Toggle("开机自动启动", isOn: $launchAtLogin)
                                    .onChange(of: launchAtLogin) { newValue in
                                        toggleLaunchAtLogin(newValue)
                                    }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                Toggle("自动粘贴", isOn: $enableAutopaste)
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label("数据", systemImage: "externaldrive")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 0) {
                            SettingRow {
                                HStack {
                                    Text("当前记录数")
                                    Spacer()
                                    Text("\(clipboardManager.items.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                HStack {
                                    Text("历史上限")
                                    Spacer()
                                    Picker("", selection: $maxHistoryItems) {
                                        ForEach(limitOptions, id: \.value) { option in
                                            Text(option.label).tag(option.value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .onChange(of: maxHistoryItems) { _ in
                                        // 调低上限时立即裁剪
                                        clipboardManager.trimToMaxItems()
                                    }
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                Button(action: { showingClearAlert = true }) {
                                    HStack {
                                        Text("清空所有历史")
                                        Spacer()
                                        Image(systemName: "trash")
                                    }
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                Button(action: exportFavorites) {
                                    HStack {
                                        Text("导出收藏夹")
                                        Spacer()
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Label("关于", systemImage: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 0) {
                            SettingRow {
                                HStack {
                                    Text("应用名称")
                                    Spacer()
                                    Text("CopyList")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                HStack {
                                    Text("版本")
                                    Spacer()
                                    Text(appVersion)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                HStack {
                                    Text("构建时间")
                                    Spacer()
                                    Text(buildTime)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                Button(action: { checkForUpdates() }) {
                                    HStack {
                                        Text("检查更新")
                                        Spacer()
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }

                            AboutAuthorRows()
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 320, height: 450)
        .alert("确认清空所有历史？", isPresented: $showingClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                clipboardManager.clearAll()
            }
        } message: {
            Text("此操作将删除所有历史记录（不含收藏），无法恢复")
        }
        .alert("更新检查", isPresented: $showUpdateAlert) {
            Button("前往下载") {
                if let url = URL(string: "https://github.com/Mr-Sure/CopyList/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("好的", role: .cancel) { }
        } message: {
            Text(updateMessage)
        }
    }
    
    private func toggleLaunchAtLogin(_ enabled: Bool) {
        let appPath = Bundle.main.bundleURL.path
        let appName = Bundle.main.bundleURL.lastPathComponent.replacingOccurrences(of: ".app", with: "")
        
        if enabled {
            let script = """
            tell application "System Events"
                make new login item at end with properties {path:"\(appPath)", hidden:false, name:"\(appName)"}
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Failed to enable launch at login: \(error)")
                }
            }
        } else {
            let script = """
            tell application "System Events"
                try
                    delete login item "\(appName)"
                end try
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("Failed to disable launch at login: \(error)")
                }
            }
        }
    }
    
    private func exportFavorites() {
        guard let exportURL = clipboardManager.exportFavorites() else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportURL.lastPathComponent
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        
        panel.begin { response in
            if response == .OK, let destination = panel.url {
                try? FileManager.default.copyItem(at: exportURL, to: destination)
            }
        }
    }
    
    private func checkForUpdates() {
        let url = URL(string: "https://raw.githubusercontent.com/Mr-Sure/CopyList/master/version.json")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let latestVersion = json["version"] as? String else {
                    self.updateMessage = "无法检查更新，请检查网络连接"
                    self.showUpdateAlert = true
                    return
                }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                if self.compareVersions(current, latestVersion) {
                    self.updateMessage = "发现新版本 \(latestVersion)\n当前版本: \(current)"
                    self.showUpdateAlert = true
                } else {
                    self.updateMessage = "当前已是最新版本 (\(current))"
                    self.showUpdateAlert = true
                }
            }
        }.resume()
    }
    
    private func compareVersions(_ current: String, _ latest: String) -> Bool {
        let c = current.split(separator: ".").compactMap { Int($0) }
        let l = latest.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, l.count) {
            let cv = i < c.count ? c[i] : 0
            let lv = i < l.count ? l[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }
}

struct SettingRow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 关于区块中的作者信息行（作者、邮箱、GitHub）
/// 拆分为独立视图以规避 SwiftUI ViewBuilder 10 个子视图的上限
struct AboutAuthorRows: View {
    var body: some View {
        Divider().padding(.leading, 16)

        SettingRow {
            HStack {
                Text("作者")
                Spacer()
                Text("Sure")
                    .foregroundColor(.secondary)
            }
        }

        Divider().padding(.leading, 16)

        SettingRow {
            Button(action: {
                if let url = URL(string: "mailto:sure@tuiyilin.com") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Text("邮箱")
                    Spacer()
                    Text("sure@tuiyilin.com")
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }

        Divider().padding(.leading, 16)

        SettingRow {
            Button(action: {
                if let url = URL(string: "https://github.com/Mr-Sure") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Text("GitHub")
                    Spacer()
                    Text("Mr-Sure")
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }
}
