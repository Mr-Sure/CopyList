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
}
