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
  -framework ImageIO \
  -framework UniformTypeIdentifiers

echo "复制 Info.plist..."
cp Info.plist CopyList.app/Contents/

echo "代码签名..."
codesign --force --deep --sign - --entitlements CopyList.entitlements CopyList.app

echo "验证签名..."
codesign -vvv CopyList.app

echo "安装到 /Applications..."
killall CopyList 2>/dev/null || true
sleep 1
rm -rf /Applications/CopyList.app
cp -r CopyList.app /Applications/

echo "✅ 完成！启动应用..."
open /Applications/CopyList.app

# ============ 打包 dmg ============
echo ""
echo "📦 打包 dmg..."

# 备份旧 dmg（若存在），便于回滚
if [ -f CopyList.dmg ]; then
  cp CopyList.dmg CopyList.dmg.bak
  echo "   旧 dmg 已备份为 CopyList.dmg.bak"
fi

# 准备 dmg 暂存目录：CopyList.app + Applications 软链接 + 权限说明
STAGING_DIR="$(mktemp -d)/CopyList"
mkdir -p "$STAGING_DIR"
cp -R CopyList.app "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
# 可选：放入权限说明文档（存在才拷贝）
for f in 开启自动粘贴权限.md 重置辅助功能权限.md; do
  [ -f "$f" ] && cp "$f" "$STAGING_DIR/"
done

# 生成 dmg（UDZO 压缩，最大化压缩级别）
rm -f CopyList.dmg
hdiutil create \
  -volname "CopyList" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  CopyList.dmg

# 清理暂存目录
TMP_ROOT="$(dirname "$STAGING_DIR")"
rm -rf "$TMP_ROOT"

echo "✅ dmg 打包完成：$(pwd)/CopyList.dmg"

echo ""
echo "提示：首次安装后，只需在「系统设置 → 隐私与安全性 → 辅助功能」中授权一次"
echo "之后重新安装不需要再次授权"
