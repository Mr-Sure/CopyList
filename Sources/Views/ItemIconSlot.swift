import SwiftUI
import AppKit

/// 列表项左侧的统一图标槽（状态栏弹窗与主窗口共用）。
///
/// 三类内容共用同一槽位尺寸、圆角与对齐方式：
/// - 文本 / 文件：低饱和度**类型底色容器** + 类型符号
/// - 图片：缩略图铺满容器；**加载中 / 加载失败时与其它类型完全同构**（样式退化为
///   「底色 + 符号」），因此不会出现「实心灰块」这种特例
///
/// 抽成共享组件的背景：此前两类视图各自硬编码图标尺寸，图片项用 48pt 缩略图、
/// 其它项用 36pt 符号槽，导致图片行的预览文本左起点比其它行右移，列表左边缘参差，
/// 图片行可用的文本宽度也更窄。
struct ItemIconSlot: View {
    let item: ClipboardItem
    /// 槽位边长（pt）：状态栏弹窗 40、主窗口列表 28
    var size: CGFloat
    /// 已解码的缩略图（仅图片类型有意义；nil 表示加载中或加载失败）
    var image: NSImage?
    /// 图片加载失败：显示错误符号而不是一直停留在「加载中」的语义
    var imageLoadFailed: Bool = false

    /// 圆角 ≈ 边长的 0.22，贴近 macOS 图标观感
    private var cornerRadius: CGFloat { (size * 0.22).rounded() }
    /// 符号字号 ≈ 边长的 0.42，保证三类行在各自尺寸下的视觉重量一致
    private var symbolSize: CGFloat { (size * 0.42).rounded() }

    /// 极端长宽比阈值：长截图 / 超宽图（如 5:1）改用 fit 完整显示，
    /// 避免按 fill 裁剪后只剩中间一条，反而认不出是什么图
    private static let extremeAspectRatio: CGFloat = 3

    var body: some View {
        Group {
            if item.type == .image, let thumbnail = image {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: needsFit(thumbnail) ? .fit : .fill)
                    .frame(width: size, height: size)
                    // fit 时的留白底色：避免出现透明「破洞」，与容器风格保持一致
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .accessibilityLabel("图片")
            } else {
                // 文本、文件，以及图片的加载中/失败态：同一套容器 + 符号
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(iconColor.opacity(0.12))
                    .overlay(
                        Image(systemName: symbolName)
                            .font(.system(size: symbolSize))
                            .foregroundColor(iconColor)
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }

    /// 图片加载失败时换成错误符号；其余情况用类型符号
    private var symbolName: String {
        if item.type == .image, imageLoadFailed {
            return "photo.badge.exclamationmark"
        }
        return Self.iconName(for: item.type)
    }

    private var iconColor: Color {
        Self.iconColor(for: item.type)
    }

    private func needsFit(_ image: NSImage) -> Bool {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return false }
        return max(width, height) / min(width, height) > Self.extremeAspectRatio
    }

    // MARK: - 类型样式（供各处复用，避免同一套映射散落多份）

    static func iconName(for type: ClipboardItem.ItemType) -> String {
        switch type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    static func iconColor(for type: ClipboardItem.ItemType) -> Color {
        switch type {
        case .text: return .blue
        case .image: return .green
        case .file: return .orange
        }
    }
}

// MARK: - 缩略图加载

/// 列表缩略图的统一加载策略（状态栏弹窗与主窗口共用，避免两处逻辑漂移）：
/// 缓存命中时同步回调（立即显示，不进异步路径），否则后台解码后回主线程赋值，
/// 保证列表滚动时主线程不被磁盘 I/O 与 ImageIO 解码阻塞。
enum ClipboardThumbnailLoader {
    static func load(filename: String,
                     manager: ClipboardManager,
                     completion: @escaping (NSImage?) -> Void) {
        if let cached = manager.getCachedImage(for: filename) {
            completion(cached)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let image = manager.getImage(for: filename)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
