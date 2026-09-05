import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("enableAutopaste") private var enableAutopaste = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var showingClearAlert = false
    @State private var showUpdateAlert = false
    @State private var updateMessage = ""
    @State private var showExportResult = false
    @State private var exportResultMessage = ""
    @State private var loginItemErrorMessage: String? = nil
    
    /// 从 Bundle 动态读取版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }
    /// 从 Bundle 动态读取构建时间
    private var buildTime: String {
        Bundle.main.infoDictionary?["CLBuildTime"] as? String ?? "未知"
    }
    
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
                            if let loginItemErrorMessage {
                                Text(loginItemErrorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
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
                                    Text("\(clipboardManager.totalItemCount)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                HStack {
                                    Text("历史保存")
                                    Spacer()
                                    Text("最近 \(ClipboardManager.maxHistoryItems) 条（收藏永久）")
                                        .foregroundColor(.secondary)
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
        .onAppear {
            // 以系统真实登录项状态同步开关，避免“系统里已删除但开关仍显示开”
            syncLaunchAtLoginState()
        }
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
        .alert("导出收藏夹", isPresented: $showExportResult) {
            Button("好的", role: .cancel) { }
        } message: {
            Text(exportResultMessage)
        }
    }

    /// 读取系统登录项真实状态（优先 SMAppService，旧方式兜底）
    private func syncLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            return
        }
        launchAtLogin = loginItemExists(named: appName())
    }

    private func appName() -> String {
        Bundle.main.bundleURL.lastPathComponent.replacingOccurrences(of: ".app", with: "")
    }

    private func loginItemExists(named name: String) -> Bool {
        let script = """
        tell application "System Events"
            try
                get login item "\(name)"
                return true
            on error
                return false
            end try
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        let output = appleScript.executeAndReturnError(&error)
        return error == nil && output.booleanValue
    }

    /// 删除旧版本（≤1.3.21）通过 AppleScript 写入的登录项（若存在）。
    /// 静默执行：未授权自动化时删除不了也不影响新流程。
    private func removeLegacyLoginItem() {
        let script = """
        tell application "System Events"
            try
                delete login item "\(appName())"
            end try
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            _ = appleScript.executeAndReturnError(&error)
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        // 优先使用 SMAppService（macOS 13+）：无需“控制 System Events”自动化授权，状态可查询
        if #available(macOS 13.0, *) {
            do {
                try applyLaunchAtLogin(enabled)
                if enabled, SMAppService.mainApp.status == .requiresApproval {
                    loginItemErrorMessage = "已申请开机自启，请在 系统设置 → 通用 → 登录项 中批准"
                    return
                }
                loginItemErrorMessage = nil
                return
            } catch {
                // 注册失败的常见原因：系统设置里存在被禁用的同名旧登录项。删旧项后重试一次
                removeLegacyLoginItem()
                do {
                    try applyLaunchAtLogin(enabled)
                    loginItemErrorMessage = nil
                } catch {
                    loginItemErrorMessage = "开机自启设置失败：\(error.localizedDescription)"
                    NSLog("CopyList: SMAppService 登录项设置失败: \(error)")
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
                return
            }
        }

        // 旧系统兜底：AppleScript 登录项
        let appPath = Bundle.main.bundleURL.path
        let name = appName()
        let script: String
        if enabled {
            script = """
            tell application "System Events"
                make new login item at end with properties {path:"\(appPath)", hidden:false, name:"\(name)"}
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                try
                    delete login item "\(name)"
                end try
            end tell
            """
        }
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                loginItemErrorMessage = "开机自启设置失败：\(error)"
                NSLog("CopyList: 登录项设置失败: \(error)")
            } else {
                loginItemErrorMessage = nil
            }
        }
    }

    /// 幂等地切换 SMAppService 登录项；切换前清理旧版 AppleScript 登录项避免并存
    @available(macOS 13.0, *)
    private func applyLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            // 升级兼容：旧版本（≤1.3.21）用 AppleScript 写的登录项仍存在时先删除，
            // 避免升级后新旧两套登录项并存导致双重自启
            removeLegacyLoginItem()
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
    
    private func exportFavorites() {
        guard let exportURL = clipboardManager.exportFavorites() else {
            // 收藏夹为空时给出可见反馈，而不是按钮无响应
            exportResultMessage = "收藏夹为空，没有可导出的内容"
            showExportResult = true
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportURL.lastPathComponent
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destination = panel.url else {
                // 用户取消保存：清理临时导出文件
                try? FileManager.default.removeItem(at: exportURL)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: exportURL, to: destination)
                exportResultMessage = "已导出到：\(destination.path)"
            } catch {
                exportResultMessage = "导出失败：\(error.localizedDescription)"
            }
            // 清理临时导出文件
            try? FileManager.default.removeItem(at: exportURL)
            showExportResult = true
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
