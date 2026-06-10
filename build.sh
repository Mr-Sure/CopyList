#!/bin/bash

set -e

echo "编译 CopyList..."
swiftc -parse-as-library \
  -o CopyList.app/Contents/MacOS/CopyList \
  ClipboardApp.swift \
  ClipboardManager.swift \
  PopoverView.swift \
  SettingsView.swift \
  -framework SwiftUI \
  -framework AppKit \
  -framework ServiceManagement \
  -framework CoreGraphics \
  -framework UniformTypeIdentifiers

echo "复制 Info.plist..."
cp Info.plist CopyList.app/Contents/

echo "代码签名..."
codesign --force --deep --sign - CopyList.app

echo "验证签名..."
codesign -vvv CopyList.app

echo "安装到 /Applications..."
killall CopyList 2>/dev/null || true
sleep 1
rm -rf /Applications/CopyList.app
cp -r CopyList.app /Applications/

echo "✅ 完成！启动应用..."
open /Applications/CopyList.app

echo ""
echo "提示：首次安装后，只需在「系统设置 → 隐私与安全性 → 辅助功能」中授权一次"
echo "之后重新安装不需要再次授权"
