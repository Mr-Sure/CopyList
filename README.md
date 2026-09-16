# CopyList

> macOS 剪贴板历史管理工具 — 轻量、高效、开源

[![License](https://img.shields.io/github/license/Mr-Sure/CopyList)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Mr-Sure/CopyList)](https://github.com/Mr-Sure/CopyList/releases)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)

一款纯 Swift 原生开发的 macOS 剪贴板管理工具，常驻状态栏，记录你的每一次复制，支持文本、图片、文件三种类型，一键复制 + 自动粘贴，让效率翻倍。

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| 📋 历史记录 | 支持文本、图片、文件，SQLite 永久保存 |
| ⭐ 收藏夹 | 常用内容一键收藏，永久保存至手动删除 |
| 🏷️ 标签管理 | 为收藏项添加标签，分类筛选；行内折叠展示 + hover 展开全部 |
| 🔍 搜索过滤 | 按类型、关键词快速检索，**正文与标签同时匹配** |
| 🎯 自动粘贴 | 点击即复制+粘贴（需辅助功能权限） |
| 🚀 开机自启 | 随系统启动，无感运行 |
| 🗑️ 内容去重 | 相同内容自动合并，不占空间 |
| 💾 自动备份 | 收藏夹每小时自动备份 |
| 🗃️ 本地数据库 | 历史按页加载，海量记录也保持流畅 |
| 📤 导出功能 | 一键导出收藏夹为 JSON |
| 🔄 自动更新 | 应用内检查新版本，一键下载 |
| 🧠 内存优化 | NSCache LRU 淘汰 + 内存压力响应 |

## 📸 截图预览

<p align="left">
  <img src="Docs/p1.jpeg" alt="CopyList Screenshot" width="400"> 
</p>

<p align="left">
  <img src="Docs/p2.png" alt="CopyList Screenshot" width="400">
</p>

## 📥 安装方式

### 方式一：下载 DMG（推荐）

前往 [Releases](https://github.com/Mr-Sure/CopyList/releases) 页面下载最新版 `CopyList.dmg`，双击打开后将 `CopyList.app` 拖入 `Applications` 文件夹。

### 方式二：从源码编译

```bash
# 克隆仓库
git clone https://github.com/Mr-Sure/CopyList.git
cd CopyList

# 运行构建脚本（自动编译、打包、安装）
bash Scripts/build.sh
```

## 🔧 系统要求

- **macOS 13.0** 或更高版本
- 自动粘贴功能需要授予**辅助功能权限**（首次启动时引导）

## 📖 使用说明

1. **启动**：安装后打开 CopyList，状态栏会出现剪贴板图标
2. **复制**：正常使用 Cmd+C 复制任何内容，CopyList 自动记录
3. **粘贴**：点击状态栏图标 → 点击历史项 → 自动粘贴到当前应用
4. **收藏**：点击 ⭐ 按钮收藏重要内容
5. **搜索**：在搜索框输入关键词过滤历史
6. **设置**：点击齿轮图标配置自动粘贴、历史上限等

## 🔨 构建说明

项目使用 `build.sh` 一键发布，完整流程：

```
版本自动递增 → Swift 编译 → 代码签名 → DMG 打包 → Git 提交 → 打 tag → 推送 → GitHub Release
```

发布前只需在 [CHANGELOG.md](CHANGELOG.md) 顶部写好本次版本条目，脚本会自动把它生成 **commit message 正文** 与 **Release notes**。完整规范、环境变量开关与 AI 自动化约定见 [Docs/发布流程.md](Docs/发布流程.md)。

### 签名证书（推荐先执行一次）

构建脚本优先使用固定自签名证书 `CopyListDev` 签名，固定的签名身份让**版本更新后辅助功能等系统授权自动保留**（ad-hoc 签名每次构建身份都变，更新即丢失授权）：

```bash
# 首次构建前运行一次（有效期 10 年，过程中如弹出钥匙串确认框请允许）
bash Scripts/create-signing-cert.sh
```

证书缺失时构建脚本会自动回退 ad-hoc 签名并提示。换机迁移请从「钥匙串访问」导出含私钥的 `CopyListDev.p12` 备份。

### 手动编译

```bash
swiftc -parse-as-library \
  -o CopyList.app/Contents/MacOS/CopyList \
  Sources/App/ClipboardApp.swift \
  Sources/Core/ClipboardManager.swift \
  Sources/Core/ClipboardStore.swift \
  Sources/Core/UpdateChecker.swift \
  Sources/Views/PopoverView.swift \
  Sources/Views/SettingsView.swift \
  Sources/Views/MainWindowView.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -lsqlite3
```

### DMG 打包

```bash
hdiutil create -volname "CopyList" -srcfolder CopyList.app -ov -format UDZO CopyList.dmg
```

## 🔐 权限说明

| 权限 | 用途 | 是否必须 |
|------|------|----------|
| 辅助功能 | 自动粘贴（模拟 Cmd+V） | 可选 |

详见：
- [开启自动粘贴权限](Docs/开启自动粘贴权限.md)
- [重置辅助功能权限](Docs/重置辅助功能权限.md)

## 📂 项目结构

```
CopyList/
├── Sources/                    # 源代码
│   ├── App/                    # 应用入口
│   │   └── ClipboardApp.swift  # AppDelegate、状态栏图标装配与生命周期
│   ├── Core/                   # 核心业务逻辑
│   │   ├── ClipboardManager.swift # 剪贴板监控、缓存、分页查询
│   │   ├── ClipboardStore.swift   # SQLite 存储层与去重
│   │   └── UpdateChecker.swift    # 版本更新检查
│   └── Views/                  # 视图层
│       ├── PopoverView.swift    # 状态栏弹出窗口
│       ├── MainWindowView.swift # 主窗口（备用）
│       ├── ItemIconSlot.swift   # 列表项统一图标槽（弹窗与主窗口共用）
│       └── SettingsView.swift   # 设置界面
├── Resources/                  # 资源文件
│   ├── Info.plist              # 应用配置
│   ├── CopyList.entitlements   # 权限声明
│   ├── AppIcon.iconset/        # 应用图标源（构建时生成 icns）
│   └── statusbar_icon.png      # 状态栏图标
├── Scripts/                    # 构建脚本
│   ├── build.sh                # 一键发布（版本/编译/签名/DMG/提交/推送/Release）
│   ├── create-signing-cert.sh  # 创建/检查自签名代码签名证书
│   └── watch_logs.sh           # 日志监控
├── Docs/                       # 文档
│   ├── 发布流程.md             # 发布规范与 AI 自动化契约
│   ├── 开启自动粘贴权限.md      # 权限引导
│   ├── 重置辅助功能权限.md      # 权限重置引导
│   └── wechat_qrcode.jpg       # 公众号二维码
├── CHANGELOG.md                # 完整更新日志（发布文案唯一数据源）
├── README.md                   # 项目说明
└── LICENSE                     # MIT 许可证
```

## 📋 更新日志

> 完整变更历史见 [CHANGELOG.md](CHANGELOG.md) —— 它是发布文案的唯一数据源，`build.sh` 会据此自动生成 commit message 与 Release notes。下方仅列最近三次发布。

### v1.3.24 (2026-09-14) — 全屏图标与列表布局修复

- 修复：**全屏下状态栏图标偶发不显示或找不到** — 图标资源改为多路径查找（App 包 → `resourcePath` → 源码目录），全部失败时回退系统符号并记录日志，不再静默留空；图标按屏幕倍率预渲染为 18pt 位图，并在切换空间、进出全屏、屏幕参数变化时重新提交重绘
- 修复：**构建产物缺失状态栏图标** — `build.sh` 此前从未拷贝 `statusbar_icon.png`，全新 clone 构建出的 App/DMG 完全没有图标，现已在打包阶段补齐
- 修复：**列表序号溢出** — 序号列固定 24pt，放不下 3 位以上序号，现按位数动态加宽
- 修复：**标签过多或过长撑破整行** — 标签最大宽度约束失效导致长标签溢出遮挡相邻内容；展开标签流对首个超宽标签不换行造成横向溢出，均已修复
- 优化：行内标签上限 96pt → 64pt，时间戳、次数、`+N` 徽标提升布局优先级，关键信息不再被挤出可视区

### v1.3.23 (2026-09-06)
- 修复：**搜索支持标签** — 此前搜索只匹配剪贴板正文，现在**正文或标签命中都会返回**（如某条记录打了"安全"标签，搜索"安全"即可找到，即使正文里没有这两个字）
- 优化：**标签展示重构** — 行内最多显示 2 个标签胶囊，超出折叠为 `+N` 徽标；长标签自动截断，不再挤爆时间戳行
- 新增：hover 时间戳行**原地展开完整标签流**（流式换行，最多 9 个 + `+N`），预览文本自动缩为一行补偿高度，移开后自动收回
- 改进：改用**固定自签名证书**（CopyListDev）签名 — 本次更新后重新授权一次辅助功能，**此后所有版本更新不再需要重复授权**
- 开发者：新增 `Scripts/create-signing-cert.sh` 一键创建/检查签名证书；构建脚本证书缺失时自动回退 ad-hoc 并提示；Release tag 包含完整源码

### v1.3.22 (2026-09-05)
- 新增：内容去重 — 同一段文本重复复制不再新增冗余记录，仅刷新时间戳与复制次数
- 新增：图片按内容指纹去重 — 同一张图片反复复制不再落盘新文件，减轻存储占用
- 优化：GIF 动图保留原始字节，从浏览器等复制 GIF 不再被强制转成静态 PNG
- 修复：搜索对 `%`、`_`、`\` 等特殊字符按字面匹配，避免搜索误导
- 修复：阻止包含引号/反斜杠的标签破坏数据与匹配
- 优化：编辑成重复内容时合并收藏/次数/标签，不丢失任何用户数据
- 优化：历史上限清理绝不触碰收藏记录，也不误删仍被引用的图片文件
- 修复：数据库损坏时自动隔离为 `.corrupt` 备份再重建，保留坏文件供人工恢复
- 修复：筛选标签被移除时自动退出筛选，避免列表"隐形筛选"莫名变空
- 优化：升级时自动清理旧版 AppleScript 登录项，避免双重自启
- 优化：自动粘贴默认值同步（一次性迁移，老用户升级自动保持原有行为）

> 更早版本（v1.0.0 ~ v1.3.21）的完整记录已迁移至 [CHANGELOG.md](CHANGELOG.md)。

## 👤 作者

**Sure**

- 📧 Email: sure@tuiyilin.com
- 🌐 GitHub: [Mr-Sure](https://github.com/Mr-Sure)

<p>关注公众号，获取更多工具推荐和技术分享：</p>

<p align="left">
  <img src="https://raw.githubusercontent.com/Mr-Sure/CopyList/master/Docs/wechat_qrcode.jpg" alt="公众号二维码" width="200">
</p>

## 🔗 友链

- [LINUX DO](https://linux.do) — 新的理想型社区
- [心心念念日](https://days.bettersun.cn) — 纪念日管理

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源。

---

<p align="center">
  如果这个项目对你有帮助，请给一个 ⭐️ Star 支持！
</p>
