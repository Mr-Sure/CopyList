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
| 📋 历史记录 | 支持文本、图片、文件，最高 5000 条 |
| ⭐ 收藏夹 | 常用内容一键收藏，永不过期 |
| 🏷️ 标签管理 | 为收藏项添加标签，分类筛选 |
| 🔍 搜索过滤 | 按类型、关键词快速检索 |
| 🎯 自动粘贴 | 点击即复制+粘贴（需辅助功能权限） |
| 🚀 开机自启 | 随系统启动，无感运行 |
| 🗑️ 内容去重 | 相同内容自动合并，不占空间 |
| 💾 自动备份 | 收藏夹每小时自动备份 |
| 📤 导出功能 | 一键导出收藏夹为 JSON |
| 🔄 自动更新 | 应用内检查新版本，一键下载 |
| 🧠 内存优化 | NSCache LRU 淘汰 + 内存压力响应 |

## 📸 截图

<p align="center">
  <img src="Docs/screenshot.png" alt="CopyList Screenshot" width="400">
</p>

## 📥 安装

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

项目使用 `build.sh` 一键构建，完整流程：

```
版本自动递增 → Swift 编译 → 代码签名 → DMG 打包 → Git 提交 → GitHub Release
```

### 手动编译

```bash
swiftc -parse-as-library \
  -o CopyList.app/Contents/MacOS/CopyList \
  Sources/App/ClipboardApp.swift \
  Sources/Core/ClipboardManager.swift \
  Sources/Core/UpdateChecker.swift \
  Sources/Views/PopoverView.swift \
  Sources/Views/SettingsView.swift \
  Sources/Views/MainWindowView.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework UniformTypeIdentifiers
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
│   │   └── ClipboardApp.swift  # AppDelegate & 应用生命周期
│   ├── Core/                   # 核心业务逻辑
│   │   ├── ClipboardManager.swift # 剪贴板监控、存储、缓存
│   │   └── UpdateChecker.swift    # 版本更新检查
│   └── Views/                  # 视图层
│       ├── PopoverView.swift   # 状态栏弹出窗口
│       ├── SettingsView.swift  # 设置界面
│       └── MainWindowView.swift # 主窗口（备用）
├── Resources/                  # 资源文件
│   ├── Info.plist              # 应用配置
│   ├── CopyList.entitlements   # 权限声明
│   ├── AppIcon.iconset/        # 应用图标
│   └── statusbar_icon.png      # 状态栏图标
├── Scripts/                    # 构建脚本
│   ├── build.sh                # 自动化构建
│   └── watch_logs.sh           # 日志监控
├── Docs/                       # 文档
│   ├── wechat_qrcode.jpg       # 公众号二维码
│   ├── 开启自动粘贴权限.md      # 权限引导
│   └── 重置辅助功能权限.md      # 权限重置引导
├── README.md                   # 项目说明
└── LICENSE                     # MIT 许可证
```

## 📋 更新日志

### v1.3.9 (2026-06-16)
- 新增：设置「关于」区块展示作者信息（作者、邮箱、GitHub）
- 邮箱点击调用系统邮件客户端，GitHub 点击打开作者主页

### v1.3.7 (2026-06-16)
- 修复：更新检查功能分支名称错误（main → master）

### v1.3.5 (2026-06-16)
- 重构：项目目录工程化改造
  - Sources/ — 源代码（App/Core/Views）
  - Resources/ — 资源文件
  - Scripts/ — 构建脚本
  - Docs/ — 文档
- 优化：build.sh 适配新目录结构

### v1.3.2 (2026-06-16)
- 新增：GitHub 自动化 Release 发布
- 新增：构建时自动检测代码变更并递增版本号
- 新增：设置界面动态显示版本号和构建时间
- 新增：设置内检查更新按钮
- 修复：更新检查 task 未启动的问题
- 优化：每 5 分钟自动清理图片缓存，降低内存占用
- 优化：Popover 关闭时自动落盘待写数据

### v1.2.1 (2025-06-11)
- 修复：自动粘贴功能恢复正常
- 修复：窗口崩溃问题
- 新增：收藏夹自动备份（每小时，保留 10 个）
- 新增：一键导出收藏夹为 JSON
- 新增：代码签名支持，辅助功能权限持久化
- 新增：build.sh 自动构建脚本
- 优化：回退到稳定的 Popover 窗口设计

### v1.2.0 (2025-06-11)
- 新增：右键删除单条记录
- 新增：收藏夹标签功能（添加/移除/筛选）
- 新增：标签可视化显示
- 优化：删除操作无需二次确认

### v1.1.0 (2025-06-11)
- 新增：开机自动启动功能
- 新增：自动粘贴开关
- 新增：内容自动去重
- 优化：商业级设置界面

### v1.0.0 (2025-06-11)
- 初始版本发布

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
