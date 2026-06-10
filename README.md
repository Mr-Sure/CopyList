# CopyList

macOS 剪贴板历史管理工具，支持文本、图片、文件历史记录。

## 功能特性

- 📋 剪贴板历史记录（文本、图片、文件）
- ⭐ 收藏夹功能
- 🏷️ 标签管理（仅收藏项）
- 🔍 搜索过滤 & 标签筛选
- 🎯 自动粘贴（可选）
- 🚀 开机自动启动
- 🗑️ 内容去重 & 右键删除
- 🎨 商业级 UI 设计

## 版本

当前版本：v1.2.0
构建日期：2025-06-11

## 系统要求

- macOS 13.0+
- 需要辅助功能权限（用于自动粘贴）

## 安装

1. 打开 `CopyList.dmg`
2. 拖动 `CopyList.app` 到 `Applications` 文件夹
3. 首次运行时授予辅助功能权限

## 使用

- 点击状态栏图标打开剪贴板历史
- 点击历史项复制/粘贴
- 点击 ⭐ 添加到收藏夹
- 右键点击项目删除或添加标签
- 点击设置按钮配置功能

## 编译

```bash
swiftc -parse-as-library \
  -o CopyList.app/Contents/MacOS/CopyList \
  ClipboardApp.swift \
  ClipboardManager.swift \
  PopoverView.swift \
  SettingsView.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework CoreGraphics
```

## 打包

```bash
hdiutil create -volname "CopyList" -srcfolder CopyList.app -ov -format UDZO CopyList.dmg
```

## 权限说明

参见：
- `开启自动粘贴权限.md`
- `重置辅助功能权限.md`

## 更新日志

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

## 许可

私有项目
