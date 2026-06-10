# CopyList

macOS 剪贴板历史管理工具，支持文本、图片、文件历史记录。

## 功能特性

- 📋 剪贴板历史记录（文本、图片、文件）
- ⭐ 收藏夹功能
- 🔍 搜索过滤
- 🎯 自动粘贴（可选）
- 🚀 开机自动启动
- 🗑️ 内容去重
- 🎨 商业级 UI 设计

## 版本

当前版本：v1.1.0
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

## 许可

私有项目
