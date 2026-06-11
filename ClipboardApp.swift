import SwiftUI
import AppKit

@main
struct ClipboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var clipboardManager: ClipboardManager!
    var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardManager = ClipboardManager()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconPath = Bundle.main.resourcePath?.appending("/statusbar_icon.png"),
               let icon = NSImage(contentsOfFile: iconPath) {
                icon.size = NSSize(width: 18, height: 18)
                icon.isTemplate = false
                button.image = icon
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 600)
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(clipboardManager))
        
        NSApp.setActivationPolicy(.accessory)
        
        // 检查辅助功能权限（延迟2秒，确保应用完全启动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkAccessibilityPermission()
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    @objc func closePopover() {
        popover.performClose(nil)
    }
    
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        
        if !trusted {
            NSLog("CopyList: ⚠️ 未检测到辅助功能权限")
            
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "CopyList 需要辅助功能权限来实现自动粘贴功能。\n\n点击\"打开设置\"后：\n1. 在左侧找到 CopyList\n2. 勾选启用\n\n如果列表中没有 CopyList，请点击 + 号手动添加。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开设置")
            alert.addButton(withTitle: "稍后")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // 打开系统设置的辅助功能页面
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        } else {
            NSLog("CopyList: ✅ 辅助功能权限已授权")
        }
    }
}
