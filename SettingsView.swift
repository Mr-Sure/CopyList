import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("enableAutopaste") private var enableAutoP = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var showingClearAlert = false
    
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
                                Toggle("自动粘贴", isOn: $enableAutoP)
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
                                    Text("1.2.0")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            SettingRow {
                                HStack {
                                    Text("构建日期")
                                    Spacer()
                                    Text("2025-06-11")
                                        .foregroundColor(.secondary)
                                }
                            }
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
