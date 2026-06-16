#!/bin/bash

set -e

# 切换到项目根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.."

PLISTBUDDY="/usr/libexec/PlistBuddy"
PLIST="Resources/Info.plist"
GITHUB_REPO="git@github.com:Mr-Sure/CopyList.git"
GITHUB_RELEASES="https://github.com/Mr-Sure/CopyList/releases"

# ============ 版本管理 ============
echo "📋 版本管理..."

# 读取当前版本
CURRENT_VERSION=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "1.3.0")
BUILD_NUMBER=$($PLISTBUDDY -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "0")

echo "   当前版本: $CURRENT_VERSION (build $BUILD_NUMBER)"

# 检测代码变更（未提交的改动 或 自上次 version.json 更新以来的新提交）
HAS_CHANGES=false

# 检查未提交的变更（排除 Info.plist 和 version.json 自身）
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null | grep -v -E "^(Info\.plist|version\.json)$" || true)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null | grep -v -E "^(Info\.plist|version\.json)$" || true)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v -E "^(Info\.plist|version\.json)$" || true)

if [ -n "$CHANGED_FILES" ] || [ -n "$STAGED_FILES" ] || [ -n "$UNTRACKED_FILES" ]; then
    HAS_CHANGES=true
    echo "   检测到代码变更"
fi

# 递增版本号（仅在代码有变更时）
if [ "$HAS_CHANGES" = true ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    BUILD_NUMBER=$((BUILD_NUMBER + 1))
    echo "   版本号递增: $CURRENT_VERSION → $NEW_VERSION (build $BUILD_NUMBER)"
else
    NEW_VERSION="$CURRENT_VERSION"
    echo "   无代码变更，保持版本 $NEW_VERSION"
fi

# 记录构建时间
BUILD_TIME=$(date '+%Y-%m-%d %H:%M')
echo "   构建时间: $BUILD_TIME"

# 写入 Info.plist
$PLISTBUDDY -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
$PLISTBUDDY -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
$PLISTBUDDY -c "Set :CLBuildTime $BUILD_TIME" "$PLIST"

echo "   ✅ Info.plist 已更新"

# ============ 编译 ============
echo ""
echo "🔨 编译 CopyList v${NEW_VERSION}..."
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

echo "   编译成功"

# ============ 打包 App ============
echo ""
echo "📦 打包 App..."
cp Resources/Info.plist CopyList.app/Contents/

echo "🔏 代码签名..."
codesign --force --deep --sign - --entitlements Resources/CopyList.entitlements CopyList.app

echo "✅ 验证签名..."
codesign -vvv CopyList.app

# ============ 安装并启动 ============
echo ""
echo "📲 安装到 /Applications..."
killall CopyList 2>/dev/null || true
sleep 1
rm -rf /Applications/CopyList.app
cp -r CopyList.app /Applications/

echo "🚀 启动应用..."
open /Applications/CopyList.app

# ============ 生成 version.json（供远程更新检查） ============
echo ""
echo "📝 生成 version.json..."
cat > version.json << EOF
{
    "version": "$NEW_VERSION",
    "build": "$BUILD_NUMBER",
    "buildTime": "$BUILD_TIME",
    "download": "$GITHUB_RELEASES/download/v${NEW_VERSION}/CopyList.dmg",
    "releaseNotes": "$GITHUB_RELEASES/tag/v${NEW_VERSION}"
}
EOF
echo "   ✅ version.json 已生成"

# ============ 打包 DMG ============
echo ""
echo "💿 打包 DMG..."

# 备份旧 dmg（若存在）
if [ -f CopyList.dmg ]; then
  cp CopyList.dmg CopyList.dmg.bak
  echo "   旧 dmg 已备份为 CopyList.dmg.bak"
fi

# 准备 dmg 暂存目录
STAGING_DIR="$(mktemp -d)/CopyList"
mkdir -p "$STAGING_DIR"
cp -R CopyList.app "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# 放入权限说明文档（存在才拷贝）
for f in Docs/开启自动粘贴权限.md Docs/重置辅助功能权限.md; do
  [ -f "$f" ] && cp "$f" "$STAGING_DIR/"
done

# 拷贝 version.json 方便分发
cp version.json "$STAGING_DIR/"

# 生成 dmg（UDZO 压缩）
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

echo "   ✅ DMG 打包完成: $(pwd)/CopyList.dmg"

# ============ Git 操作 ============
echo ""
echo "🔄 Git 同步..."

# 确保远程仓库已配置
if ! git remote get-url origin &>/dev/null; then
    git remote add origin "$GITHUB_REPO"
    echo "   已添加远程仓库: $GITHUB_REPO"
fi

# 提交版本更新
git add Resources/Info.plist version.json
git diff --cached --quiet || git commit -m "chore: bump version to $NEW_VERSION (build $BUILD_NUMBER)"

# 创建版本标签
TAG="v${NEW_VERSION}"
if ! git tag -l "$TAG" | grep -q "$TAG"; then
    git tag -a "$TAG" -m "Release $TAG - $BUILD_TIME"
    echo "   已创建标签: $TAG"
fi

# 推送到远程
echo "   推送到 GitHub..."
CURRENT_BRANCH=$(git branch --show-current)
[ -z "$CURRENT_BRANCH" ] && CURRENT_BRANCH="main"

git push origin "$CURRENT_BRANCH" 2>&1 && echo "   ✅ 代码已推送" || echo "   ⚠️ 推送失败，请手动执行: git push origin $CURRENT_BRANCH"
git push origin "$TAG" 2>&1 && echo "   ✅ 标签已推送" || echo "   ⚠️ 标签推送失败，请手动执行: git push origin $TAG"

# ============ GitHub Release ============
echo ""
echo "🚀 GitHub Release..."

# 检查 gh CLI 是否可用
if ! command -v gh &>/dev/null; then
    echo "   ⚠️ gh CLI 未安装，跳过自动 Release"
    echo "   请手动创建: $GITHUB_RELEASES/new?tag=$TAG"
else
    # 检查 Release 是否已存在
    if gh release view "$TAG" --repo Mr-Sure/CopyList &>/dev/null; then
        echo "   Release $TAG 已存在，跳过创建"
    else
        # 仅在代码有变更时创建新 Release
        if [ "$HAS_CHANGES" = true ]; then
            # 生成 Release 说明文件
            RELEASE_NOTES_FILE=$(mktemp)
            cat > "$RELEASE_NOTES_FILE" << EOF
## 🎉 CopyList $TAG

---

### 📦 下载

| 文件 | 平台 | 说明 |
|------|------|------|
| [CopyList.dmg]($GITHUB_RELEASES/download/$TAG/CopyList.dmg) | macOS 13.0+ | 安装包，双击拖入 Applications 即可 |

### 📋 构建信息

| 项目 | 值 |
|------|-----|
| 版本号 | $TAG |
| 构建号 | $BUILD_NUMBER |
| 构建时间 | $BUILD_TIME |

### 🚀 快速开始

1. 下载 \`CopyList.dmg\` 并打开
2. 将 \`CopyList.app\` 拖入 \`Applications\` 文件夹
3. 启动 CopyList，状态栏出现图标即可使用

### 📖 相关链接

- [📖 使用文档]($GITHUB_RELEASES/tag/$TAG)
- [🐛 问题反馈](https://github.com/Mr-Sure/CopyList/issues)
- [💬 公众号](https://raw.githubusercontent.com/Mr-Sure/CopyList/master/Docs/wechat_qrcode.jpg)

---

**如果觉得好用，请给个 ⭐ Star 支持一下！**
EOF

            echo "   创建 Release $TAG..."
            gh release create "$TAG" \
                --repo Mr-Sure/CopyList \
                --title "CopyList $TAG" \
                --notes-file "$RELEASE_NOTES_FILE" \
                CopyList.dmg 2>&1

            rm -f "$RELEASE_NOTES_FILE"

            if [ $? -eq 0 ]; then
                echo "   ✅ Release 已创建并上传 DMG"
            else
                echo "   ⚠️ Release 创建失败，请手动创建: $GITHUB_RELEASES/new?tag=$TAG"
            fi
        else
            echo "   无代码变更，跳过 Release 创建"
        fi
    fi
fi

# ============ 完成 ============
echo ""
echo "=========================================="
echo "  ✅ CopyList v${NEW_VERSION} 构建完成！"
echo "  📅 构建时间: $BUILD_TIME"
echo "  📦 DMG: $(pwd)/CopyList.dmg"
echo "  🏷️  标签: $TAG"
echo "  🌐 Release: $GITHUB_RELEASES/tag/$TAG"
echo "=========================================="
