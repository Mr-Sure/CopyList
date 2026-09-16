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

extension Notification.Name {
    /// Popover 已关闭，供 SwiftUI 侧复位临时状态
    static let copyListPopoverDidClose = Notification.Name("copyListPopoverDidClose")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var clipboardManager: ClipboardManager!
    var popover: NSPopover!
    /// 最近一次 Popover 关闭时间：规避 transient 行为下点击状态栏图标“先被系统关闭、又被 toggle 重新打开”的闪烁
    private var lastPopoverCloseAt = Date.distantPast

    // MARK: - 状态栏图标
    /// 菜单栏图标基准尺寸（pt）；实际位图按屏幕缩放倍率取 @2x/@3x
    private static let statusIconPointSize = NSSize(width: 18, height: 18)
    private static let statusIconResourceName = "statusbar_icon"
    /// 是否把图标交给系统按菜单栏前景色反色绘制（模板图）。
    /// 当前资源是彩色 App 图标，内部细节（文档与线条）都是不透明像素，
    /// 模板图只取 alpha 通道 → 会退化成一块纯色圆角方块、细节全丢，
    /// 因此这里保持 false（自带高亮配色，深浅菜单栏下都可见）；
    /// 若以后换成单色描边图标，可置为 true 由系统统一接管配色。
    private static let statusIconUsesTemplate = false
    /// 状态栏项的持久化名称（`autosaveName`），**必须全局唯一**。
    ///
    /// 不设置时系统使用默认名 `Item-N`，并把「位置 / 可见性」记录写进**全局共享的**
    /// `com.apple.systemuiserver`：所有未命名的状态项（各第三方菜单栏应用）共用同一批
    /// `Item-N` 键，会互相覆盖。一旦某条记录把该项写成「不可见」，系统在**每次启动时**
    /// 都会据此把图标恢复成隐藏状态 —— 表现为「重启后状态栏里找不到图标」，
    /// 且与图标加载、重绘时机完全无关（这正是此前反复修图标渲染都无效的原因）。
    private static let statusItemAutosaveName = "com.local.copylist.statusitem"
    /// 已绘制好的图标缓存：全屏切换、空间切换时重新提交无需重复解码 3MB 原图
    private var cachedStatusIcon: NSImage?
    /// 合并短时间内的多次刷新（切换空间会连发多条通知）
    private var statusRefreshWorkItem: DispatchWorkItem?
    private var statusObservers: [NSObjectProtocol] = []
    /// 可见性看门狗：菜单栏服务重建（SystemUIServer 重启、登录切换）后不会通知应用，
    /// 只能周期性主动复查，否则状态项会一直保持隐藏
    private var statusVisibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardManager = ClipboardManager()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 唯一 autosaveName：让「位置 / 可见性」记录独立成键，避免与其它未命名状态项互相覆盖
        statusItem.autosaveName = Self.statusItemAutosaveName
        // 允许用户 ⌘ 拖动图标重新排序。
        // 菜单栏项较多时，第三方项排在靠近应用菜单的一侧；当应用菜单较宽（浏览器、编辑器等）
        // 时，应用菜单会向右延伸并把它遮住（这正是「聚焦编辑器/浏览器就看不见图标」的原因）。
        // 应用没有 API 可以指定状态项位置，唯一可行的调整方式是用户拖动重排 —— 因此打开该能力。
        // 不设置 terminationOnRemoval：拖出菜单栏只是隐藏该项，随后会被可见性看门狗恢复。
        statusItem.behavior = .removalAllowed
        _ = applyStatusItemIcon()
        // 该项此前若被隐藏（窗口已坍缩），立即恢复；恢复会重建按钮，故延后重新装配图标
        if restoreStatusItemVisibilityIfNeeded() {
            scheduleStatusBarRefresh(delay: 0.3)
        }
        startObservingStatusBarAppearance()
        startStatusItemVisibilityWatchdog()
        // 菜单栏就绪过程中系统可能再次改写可见性，延迟复查一次兜底
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if self.restoreStatusItemVisibilityIfNeeded() {
                self.scheduleStatusBarRefresh(delay: 0.3)
            }
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 600)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(clipboardManager))
        
        NSApp.setActivationPolicy(.accessory)
        
        // 检查辅助功能权限（延迟2秒，确保应用完全启动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkAccessibilityPermission()
        }
    }
    
    /// 退出前确保 pending 的防抖写盘落盘
    func applicationWillTerminate(_ notification: Notification) {
        statusRefreshWorkItem?.cancel()
        statusVisibilityTimer?.invalidate()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in statusObservers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        statusObservers.removeAll()
        clipboardManager.flushPendingSave()
    }

    // MARK: - 状态栏图标装配与自愈

    /// 装配状态栏按钮的图标与交互。
    /// `NSStatusItem` 的 `button` 在极少数启动时序下会晚于创建返回（返回 nil），
    /// 原实现用 `if let` 直接跳过赋值 → 图标整个不出现且无任何日志，这里改为带重试。
    @discardableResult
    private func applyStatusItemIcon(retry: Int = 0) -> Bool {
        guard let button = statusItem.button else {
            guard retry < 10 else {
                NSLog("CopyList: ❌ 状态栏按钮创建失败，状态栏图标无法显示")
                return false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                _ = self?.applyStatusItemIcon(retry: retry + 1)
            }
            return false
        }

        button.image = statusIcon()
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "CopyList"
        button.action = #selector(togglePopover)
        button.target = self
        // 状态栏在全屏自动隐藏后重新滑入、切换空间时可能残留未刷新的旧图层，
        // 这里主动触发一次重绘，避免“图标偶发空白”
        button.needsDisplay = true
        button.displayIfNeeded()
        return true
    }

    /// 状态项是否真的显示在菜单栏上。
    ///
    /// **不能用 `statusItem.isVisible` 判断**：实测（v1.3.25 二进制）系统把项隐藏后，
    /// 该属性依然读出 `true`，导致「读到可见 → 不恢复 → 图标永远不出现」。
    /// 而状态项被隐藏时，其窗口会**坍缩成 0×0**（正常为约 34×24），
    /// 因此以窗口宽度作为判据；窗口尚未创建时返回 nil，避免启动早期误判。
    private var statusItemVisibility: Bool? {
        guard let window = statusItem.button?.window else { return nil }
        return window.frame.width > 1
    }

    /// 复查并在必要时恢复状态项的可见性。
    ///
    /// 状态项可能被系统（菜单栏空间不足）或用户（⌘ 拖动将其移出菜单栏）标记为隐藏，
    /// 且该状态会被持久化 —— 不显式恢复的话，**重启之后会一直是隐藏的**，
    /// 这正是「重启后状态栏里找不到图标」的直接原因。
    ///
    /// - Returns: 是否执行了恢复动作（调用方需在恢复后**延后**重新装配图标）
    @discardableResult
    private func restoreStatusItemVisibilityIfNeeded() -> Bool {
        guard let statusItem, statusItemVisibility == false else { return false }

        // 重新绑定唯一 autosaveName，确保恢复动作写回我们自己的记录键，
        // 而不是与其它应用共享的默认 "Item-N"
        statusItem.autosaveName = Self.statusItemAutosaveName
        statusItem.isVisible = true
        NSLog("CopyList: 检测到状态栏项被隐藏（窗口已坍缩），已强制恢复显示")
        return true
    }

    /// 菜单栏外观变化（切换空间 / 进出全屏 / 屏幕参数变化 / 应用激活）时的统一处理：
    /// 先复查可见性，再刷新图标。
    ///
    /// 注意：`isVisible = true` 会让 AppKit **重建状态项按钮**，紧跟着写入的图标会随旧按钮
    /// 一起丢失（表现为状态项变成一条空白窄条，宽度只剩 16pt 左右），因此恢复之后必须延后装配。
    private func handleMenuBarChange() {
        if restoreStatusItemVisibilityIfNeeded() {
            scheduleStatusBarRefresh(delay: 0.3)
        } else {
            scheduleStatusBarRefresh()
        }
    }

    /// 周期性复查可见性。
    /// 菜单栏服务重建（SystemUIServer 重启、快速用户切换、登录过渡）不会发出任何通知，
    /// 状态项可能因此长期停留在隐藏状态；这里用低频轮询兜底。
    private func startStatusItemVisibilityWatchdog() {
        statusVisibilityTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 可见时零开销（仅一次属性读取），只有确实被隐藏才恢复并延后重新装配
            if self.restoreStatusItemVisibilityIfNeeded() {
                self.scheduleStatusBarRefresh(delay: 0.3)
            }
        }
        // 允许系统合并唤醒以省电；复查本身只是一次属性读取，代价可忽略
        timer.tolerance = 2
        statusVisibilityTimer = timer
    }

    /// 监听会让菜单栏重新出现的事件（切换空间 / 进入退出全屏、屏幕参数变化、App 激活），
    /// 在这些时机复查可见性并重新提交图标 —— 覆盖「进入/退出全屏后菜单栏里找不到图标」。
    private func startObservingStatusBarAppearance() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        statusObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMenuBarChange()
        })
        statusObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMenuBarChange()
        })
        statusObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMenuBarChange()
        })
    }

    /// 延迟到菜单栏窗口稳定后重新提交图标：通知到达时菜单栏图层往往还在重建，
    /// 立即写入的图标可能被接下来的重建覆盖掉，故加一个短延迟并合并连续通知。
    private func scheduleStatusBarRefresh(delay: TimeInterval = 0.1) {
        statusRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 可能换了显示器/缩放倍率，重新生成位图后重新装配图标
            self.cachedStatusIcon = nil
            _ = self.applyStatusItemIcon()
        }
        statusRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func statusIcon() -> NSImage {
        if let cachedStatusIcon { return cachedStatusIcon }
        let icon = Self.loadStatusBarIcon()
        cachedStatusIcon = icon
        return icon
    }

    /// 加载状态栏图标，并统一处理为菜单栏可用的模板位图。
    /// - 查找顺序：Bundle 资源 API → Bundle.resourcePath → 源码目录（开发期直接运行编译产物）；
    ///   原实现只认 `resourcePath + "/statusbar_icon.png"` 单一路径，且构建脚本未拷贝该资源，
    ///   一旦找不到就静默留空，表现为“图标找不到”。
    /// - 兜底：依次回退到 SF Symbol 与应用图标，保证任何环境下都必有图标。
    private static func loadStatusBarIcon() -> NSImage {
        for url in statusBarIconCandidateURLs() {
            if let image = NSImage(contentsOf: url), image.isValid {
                let icon = makeMenuBarIcon(from: image)
                icon.isTemplate = statusIconUsesTemplate
                return icon
            }
        }
        NSLog("CopyList: ⚠️ 未找到 statusbar_icon.png，回退到系统符号")
        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyList")
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage(size: statusIconPointSize)
        fallback.size = statusIconPointSize
        fallback.isTemplate = true
        return fallback
    }

    private static func statusBarIconCandidateURLs() -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.main.url(forResource: statusIconResourceName, withExtension: "png") {
            urls.append(url)
        }
        if let resources = Bundle.main.resourcePath {
            urls.append(URL(fileURLWithPath: resources)
                .appendingPathComponent("\(statusIconResourceName).png"))
        }
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(workingDirectory.appendingPathComponent("Resources/\(statusIconResourceName).png"))
        urls.append(workingDirectory.appendingPathComponent("\(statusIconResourceName).png"))
        return urls
    }

    /// 把原始图标（2048×2048 / 16bit / 3MB PNG）重绘为菜单栏实际需要的 18pt 位图。
    /// 直接使用原图时，状态栏每次重建图层都要在线缩放一张超大 16bit 位图，
    /// 在进入/退出全屏这类需要立刻出图的时机可能来不及呈现而出现空白。
    private static func makeMenuBarIcon(from source: NSImage) -> NSImage {
        let pointSize = statusIconPointSize
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = pointSize
            return source
        }
        // 模板图按 alpha 通道取形，先清空缓冲区，避免叠加到底图的脏数据
        if let data = rep.bitmapData {
            memset(data, 0, rep.bytesPerRow * rep.pixelsHigh)
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: pointSize),
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let icon = NSImage(size: pointSize)
        icon.addRepresentation(rep)
        return icon
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else if Date().timeIntervalSince(lastPopoverCloseAt) > 0.25 {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    @objc func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseAt = Date()
        clipboardManager.flushPendingSave()
        // 通知 SwiftUI 复位临时界面状态（sheet/面板），避免下次打开弹出残留面板
        NotificationCenter.default.post(name: .copyListPopoverDidClose, object: nil)
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
