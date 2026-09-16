import SwiftUI
import AppKit

/// 列表项左侧的统一图标槽（状态栏弹窗与主窗口共用）。
///
/// 三类内容共用同一槽位尺寸、圆角与对齐方式，槽内**始终显示类型图标**：
/// 文本 `doc.text`、图片 `photo`、文件 `folder`，各自配低饱和度的类型底色。
///
/// 图片缩略图预览放在**内容区**（尺寸由 `ImagePreviewMetrics` 计算），
/// 于是三种类型的语义完全一致：图标槽 = 类型，内容区 = 内容
/// （正文 / 文件名 / 图片预览）—— 此前把缩略图塞进图标槽、内容区只留「图片」两个字，
/// 造成图片行与其它行的左边缘、文本宽度都不一致。
struct ItemIconSlot: View {
    let item: ClipboardItem
    /// 槽位边长（pt）：状态栏弹窗 40、主窗口列表 28
    var size: CGFloat

    /// 圆角 ≈ 边长的 0.22，贴近 macOS 图标观感
    private var cornerRadius: CGFloat { (size * 0.22).rounded() }
    /// 符号字号 ≈ 边长的 0.42，保证三类行在各自尺寸下的视觉重量一致
    private var symbolSize: CGFloat { (size * 0.42).rounded() }
    /// 图标槽底色：中性填充，与任何内容/标签颜色都百搭。
    /// 用 `primary` 而非固定灰，浅色模式呈浅灰、深色模式呈浅白，自动适配外观。
    /// 只有符号本身保留类型色（蓝 doc / 绿 photo / 橙 folder）。
    private static let slotBackground = Color.primary.opacity(0.07)

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Self.slotBackground)
            .overlay(
                Image(systemName: Self.iconName(for: item.type))
                    .font(.system(size: symbolSize))
                    .foregroundColor(iconColor)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var iconColor: Color {
        Self.iconColor(for: item.type)
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

// MARK: - 内容区图片预览

/// 内容区缩略图的显示尺寸计算：按原图比例缩放到不超过给定上限，
/// 并限制放大倍数，避免小图被拉成模糊的色块。
enum ImagePreviewMetrics {
    static func size(for image: NSImage,
                     maxWidth: CGFloat,
                     maxHeight: CGFloat,
                     maxUpscale: CGFloat = 3) -> CGSize {
        let source = image.size
        guard source.width > 0, source.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }
        let scale = min(maxWidth / source.width, maxHeight / source.height, maxUpscale)
        return CGSize(width: max(1, (source.width * scale).rounded()),
                      height: max(1, (source.height * scale).rounded()))
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
