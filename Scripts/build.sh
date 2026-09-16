#!/bin/bash

set -e

# 切换到项目根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.."

PLISTBUDDY="/usr/libexec/PlistBuddy"
PLIST="Resources/Info.plist"
CHANGELOG="CHANGELOG.md"
GITHUB_REPO="git@github.com:Mr-Sure/CopyList.git"
GITHUB_RELEASES="https://github.com/Mr-Sure/CopyList/releases"

# ============ 运行开关（详见 Docs/发布流程.md 第六节） ============
DRY_RUN="${DRY_RUN:-0}"            # 1=只演算：不改文件、不编译、不安装、不提交、不推送
FORCE_BUMP="${FORCE_BUMP:-0}"      # 1=无代码变更也递增版本
SKIP_INSTALL="${SKIP_INSTALL:-0}"  # 1=不安装到 /Applications
SKIP_PUSH="${SKIP_PUSH:-0}"        # 1=不推送、不创建 Release（仍本地提交与打 tag）

if [ "$DRY_RUN" = "1" ]; then
    echo "🧪 DRY-RUN 模式：只演算不落地（不会修改任何文件、不推送）"
    echo ""
fi

# 有副作用的命令统一走 run()：DRY_RUN 时只打印不执行
run() {
    if [ "$DRY_RUN" = "1" ]; then
        echo "   [dry-run] $*"
    else
        "$@"
    fi
}

# 未提交 / 暂存 / 未跟踪的改动文件（排除脚本自身维护的版本文件与 CHANGELOG）
# core.quotepath=false：否则中文文件名（如 Docs/发布流程.md）会被 git 转义成 \345\217\221 形式
VERSION_FILES_PATTERN='^(Resources/)?Info\.plist$|^version\.json$|^CHANGELOG\.md$'
changed_source_files() {
    { git -c core.quotepath=false diff --name-only HEAD 2>/dev/null
      git -c core.quotepath=false diff --cached --name-only 2>/dev/null
      git -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null
    } | grep -v -E "$VERSION_FILES_PATTERN" | sort -u || true
}

# 自上次发布（version.json 最后一次变更）以来的提交
commits_since_release() {
    local last
    last=$(git log -1 --format=%H -- version.json 2>/dev/null || true)
    if [ -n "$last" ]; then
        git log --oneline --no-merges "${last}..HEAD" 2>/dev/null | grep -v "bump version to" || true
    else
        git log --oneline --no-merges -5 2>/dev/null || true
    fi
}

# 从 CHANGELOG.md 抽取指定版本条目正文：## [x.y.z] 到下一个 ## [ 之间
changelog_section() {
    local version="$1"
    [ -f "$CHANGELOG" ] || return 0
    awk -v ver="[$version]" '
        index($0, "## " ver) == 1 { inside = 1; next }
        inside && index($0, "## [") == 1 { exit }
        inside { print }
    ' "$CHANGELOG"
}

# 条目是否为空（忽略空白字符）
section_is_empty() {
    [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]
}

# 自动生成版本条目草稿：依据自上次发布以来的提交与本次改动文件
# 目的：即使忘记写 CHANGELOG，Release 说明也不会空白
changelog_draft() {
    local commits files
    commits=$(commits_since_release)
    files=$(changed_source_files)

    printf '> ⚠️ 本条为脚本自动生成的草稿，请补充「用户可感知的变化」后重新发布（见 Docs/发布流程.md）。\n\n'
    if [ -n "$commits" ]; then
        printf '### 变更\n\n%s\n\n' "$(printf '%s' "$commits" | sed 's/^/- /')"
    fi
    if [ -n "$files" ]; then
        printf '### 改动文件\n\n%s\n\n' "$(printf '%s' "$files" | sed 's/^/- `/; s/$/`/')"
    fi
}

# 把新版本条目插入 CHANGELOG.md 顶部（`## [未发布]` 之后；无该标题则插到第一个版本标题前）
insert_changelog_entry() {
    local version="$1" date="$2" body="$3" entry tmp
    entry=$(mktemp); tmp=$(mktemp)
    printf '## [%s] - %s\n\n%s\n' "$version" "$date" "$body" > "$entry"
    awk -v ef="$entry" '
        !done && /^## \[未发布\]/ {
            print; print ""
            while ((getline line < ef) > 0) print line
            close(ef); done = 1; next
        }
        !done && /^## \[/ {
            while ((getline line < ef) > 0) print line
            close(ef); done = 1
        }
        { print }
    ' "$CHANGELOG" > "$tmp"
    mv "$tmp" "$CHANGELOG"
    rm -f "$entry"
}

# 取版本条目里的首条要点作为 commit 摘要（去掉 markdown 标记与冒号后的解释）
# 跳过草稿里的「改动文件」清单（`- \`path\``），否则摘要会变成文件名
first_bullet() {
    local line
    line=$(printf '%s\n' "$1" | grep '^- ' | grep -v '^- `' | head -1 || true)
    if [ -z "$line" ]; then
        printf '版本发布\n'
        return
    fi
    # 注意：全角冒号必须作为字面量单独替换，不能写进字符类 [：:]
    # —— BSD sed 的字符类按字节处理，会把「格」等汉字的尾字节误判为匹配，
    # 从而在字符中间截断并产生乱码（如「视觉风�」）
    printf '%s' "$line" | sed -e 's/^- //' -e 's/\*\*//g' -e 's/`//g' -e 's/：.*$//' -e 's/:.*$//'
    printf '\n'
}

# ============ 版本管理 ============
echo "📋 版本管理..."

# 读取当前版本
CURRENT_VERSION=$($PLISTBUDDY -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "1.3.0")
BUILD_NUMBER=$($PLISTBUDDY -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "0")

echo "   当前版本: $CURRENT_VERSION (build $BUILD_NUMBER)"

# 变更检测：未提交改动 / 暂存改动 / 未跟踪文件 / 自上次发布以来的新提交
HAS_CHANGES=false
CHANGED_FILES=$(changed_source_files)
COMMITS_SINCE_RELEASE=$(commits_since_release)

if [ -n "$CHANGED_FILES" ]; then
    HAS_CHANGES=true
    echo "   检测到未提交改动"
elif [ -n "$COMMITS_SINCE_RELEASE" ]; then
    HAS_CHANGES=true
    echo "   检测到上次发布以来的新提交"
fi

if [ "$FORCE_BUMP" = "1" ]; then
    HAS_CHANGES=true
    echo "   FORCE_BUMP=1：强制递增版本"
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
    echo "   无代码变更，保持版本 $NEW_VERSION（需强制递增请用 FORCE_BUMP=1）"
fi

# 记录构建时间
BUILD_TIME=$(date '+%Y-%m-%d %H:%M')
RELEASE_DATE=$(date '+%Y-%m-%d')
TAG="v${NEW_VERSION}"
echo "   构建时间: $BUILD_TIME"

# 写入 Info.plist
run "$PLISTBUDDY" -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
run "$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
run "$PLISTBUDDY" -c "Set :CLBuildTime $BUILD_TIME" "$PLIST"

if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] Info.plist 未修改"
else
    echo "   ✅ Info.plist 已更新"
fi

# ============ 发布文案（CHANGELOG.md 驱动） ============
echo ""
echo "📝 生成发布文案..."

CHANGELOG_BODY=$(changelog_section "$NEW_VERSION")

if section_is_empty "$CHANGELOG_BODY"; then
    if [ "$HAS_CHANGES" = true ]; then
        echo "   ⚠️ CHANGELOG.md 缺少 [$NEW_VERSION] 条目，已自动生成草稿"
        CHANGELOG_BODY=$(changelog_draft)
        if [ "$DRY_RUN" = "1" ]; then
            echo "   [dry-run] 向 CHANGELOG.md 插入 [$NEW_VERSION] 草稿条目"
        else
            insert_changelog_entry "$NEW_VERSION" "$RELEASE_DATE" "$CHANGELOG_BODY"
        fi
    else
        echo "   ℹ️ 无变更，跳过文案生成"
    fi
else
    echo "   ✅ 使用 CHANGELOG.md 中的 [$NEW_VERSION] 条目"
fi

COMMIT_SUBJECT=$(first_bullet "$CHANGELOG_BODY")
COMMIT_MESSAGE="release(${TAG}): ${COMMIT_SUBJECT}

${CHANGELOG_BODY}

---
构建号: ${BUILD_NUMBER} | 构建时间: ${BUILD_TIME} | 产物: CopyList.dmg"

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "   ── 将要提交的 commit message ──"
    printf '%s\n' "$COMMIT_MESSAGE" | sed 's/^/   │ /'
    echo "   ──────────────────────────────"
fi

# ============ 编译 ============
echo ""
echo "🔨 编译 CopyList v${NEW_VERSION}..."
if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] 跳过编译（提交前建议先 swiftc -typecheck 验证）"
else
    swiftc -parse-as-library \
      -module-cache-path /tmp/copylist_module_cache \
      -o CopyList.app/Contents/MacOS/CopyList \
      Sources/App/ClipboardApp.swift \
      Sources/Core/ClipboardManager.swift \
      Sources/Core/ClipboardStore.swift \
      Sources/Core/UpdateChecker.swift \
      Sources/Views/PopoverView.swift \
      Sources/Views/ItemIconSlot.swift \
      Sources/Views/SettingsView.swift \
      Sources/Views/MainWindowView.swift \
      -framework SwiftUI \
      -framework AppKit \
      -framework ServiceManagement \
      -framework CoreGraphics \
      -framework ImageIO \
      -framework UniformTypeIdentifiers \
      -lsqlite3
    echo "   编译成功"
fi

# ============ 打包 App ============
echo ""
echo "📦 打包 App..."
# 运行时资源：状态栏图标缺失会让状态栏完全没有图标（图标查找失败后无任何提示），
# 脚本必须自己拷贝，否则全新 clone 构建/DMG 里没有该资源
run cp Resources/Info.plist CopyList.app/Contents/
run mkdir -p CopyList.app/Contents/Resources

if [ -f Resources/statusbar_icon.png ]; then
    run cp Resources/statusbar_icon.png CopyList.app/Contents/Resources/
    if [ "$DRY_RUN" != "1" ]; then echo "   已拷贝 statusbar_icon.png"; fi
else
    echo "   ⚠️ 缺少 Resources/statusbar_icon.png，状态栏图标将回退为系统符号"
fi

# 应用图标：优先用现成 icns，否则从 iconset 生成（缺失只影响 Finder/Dock 图标）
if [ -f Resources/AppIcon.icns ]; then
    run cp Resources/AppIcon.icns CopyList.app/Contents/Resources/
elif [ -d Resources/AppIcon.iconset ]; then
    if [ "$DRY_RUN" = "1" ]; then
        echo "   [dry-run] iconutil -c icns Resources/AppIcon.iconset"
    elif iconutil -c icns Resources/AppIcon.iconset -o CopyList.app/Contents/Resources/AppIcon.icns 2>/dev/null; then
        echo "   已从 AppIcon.iconset 生成 AppIcon.icns"
    else
        echo "   ⚠️ AppIcon.icns 生成失败（仅影响应用图标）"
    fi
fi

echo "🔏 代码签名..."
# 使用固定的自签名证书（Scripts/create-signing-cert.sh 创建），签名身份跨版本稳定，
# 辅助功能等 TCC 授权因此在版本更新后保留；证书缺失时回退 ad-hoc 签名（更新后需重新授权）
if security find-identity -v -p codesigning | grep -q '"CopyListDev"'; then
    run codesign --force --deep --sign "CopyListDev" --entitlements Resources/CopyList.entitlements CopyList.app
else
    echo "   ⚠️ 未找到 CopyListDev 证书，回退 ad-hoc 签名（更新后需重新授权辅助功能）"
    echo "   运行 Scripts/create-signing-cert.sh 创建证书后可永久解决"
    run codesign --force --deep --sign - --entitlements Resources/CopyList.entitlements CopyList.app
fi

echo "✅ 验证签名..."
if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] codesign -vvv CopyList.app"
else
    codesign -vvv CopyList.app
fi

# ============ 安装并启动 ============
echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "📲 [dry-run] 跳过安装到 /Applications 与启动"
elif [ "$SKIP_INSTALL" = "1" ]; then
    echo "📲 SKIP_INSTALL=1：跳过安装与启动"
else
    echo "📲 安装到 /Applications..."
    killall CopyList 2>/dev/null || true
    sleep 1
    # 无 /Applications 写权限时（无管理员/构建沙箱）跳过安装，不中断打包流程
    if rm -rf /Applications/CopyList.app 2>/dev/null && cp -r CopyList.app /Applications/ 2>/dev/null; then
        echo "   ✅ 已安装到 /Applications"
        echo "🚀 启动应用..."
        open /Applications/CopyList.app 2>/dev/null || true
    else
        echo "   ⚠️ 无 /Applications 写权限，跳过安装（DMG 打包不受影响）"
    fi
fi

# ============ 生成 version.json（供远程更新检查） ============
echo ""
echo "📝 生成 version.json..."
if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] version=${NEW_VERSION} build=${BUILD_NUMBER} buildTime=${BUILD_TIME}"
else
    cat > version.json << EOF
{
    "version": "$NEW_VERSION",
    "build": "$BUILD_NUMBER",
    "buildTime": "$BUILD_TIME",
    "download": "$GITHUB_RELEASES/download/${TAG}/CopyList.dmg",
    "releaseNotes": "$GITHUB_RELEASES/tag/${TAG}"
}
EOF
    echo "   ✅ version.json 已生成"
fi

# ============ 打包 DMG ============
echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "💿 [dry-run] 跳过 DMG 打包"
else
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
      if [ -f "$f" ]; then cp "$f" "$STAGING_DIR/"; fi
    done

    # 拷贝 version.json 方便分发
    cp version.json "$STAGING_DIR/"

    # 生成 dmg（UDZO 压缩）。hdiutil 在受限环境（如构建沙箱）可能被禁用，
    # 此时降级为警告而不是中断整个发布流程，其余交互可通过备注中手动补充。
    rm -f CopyList.dmg
    if hdiutil create \
      -volname "CopyList" \
      -srcfolder "$STAGING_DIR" \
      -fs HFS+ \
      -format UDZO \
      -imagekey zlib-level=9 \
      CopyList.dmg 2>&1; then
        echo "   ✅ DMG 打包完成: $(pwd)/CopyList.dmg"
    else
        echo "   ⚠️ DMG 创建失败（当前环境可能禁用 hdiutil），请在有图形界面/权限的环境手动执行：
        hdiutil create -volname CopyList -srcfolder \"$STAGING_DIR\" -fs HFS+ -format UDZO -imagekey zlib-level=9 $(pwd)/CopyList.dmg"
    fi

    # 清理暂存目录
    TMP_ROOT="$(dirname "$STAGING_DIR")"
    rm -rf "$TMP_ROOT"
fi

# ============ Git 操作 ============
echo ""
echo "🔄 Git 同步..."

# 确保远程仓库已配置
if ! git remote get-url origin &>/dev/null; then
    git remote add origin "$GITHUB_REPO"
    echo "   已添加远程仓库: $GITHUB_REPO"
fi

# 提交全部变更（源码 + 版本文件 + CHANGELOG）：保证 release tag 与实际构建产物内容一致，
# 否则 tag 只含版本号、不含本次发布的代码修复（.gitignore 会排除 dmg/app 等构建产物）
run git add -A

# commit message 由 CHANGELOG 条目生成（见「发布文案」段），保证提交记录与 Release 说明同源
COMMIT_MSG_FILE="/tmp/copylist_commit_msg.txt"
printf '%s\n' "$COMMIT_MESSAGE" > "$COMMIT_MSG_FILE"

if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] git commit -F $COMMIT_MSG_FILE"
elif git diff --cached --quiet; then
    echo "   无待提交内容"
else
    git commit -F "$COMMIT_MSG_FILE"
    echo "   ✅ 已提交: $(git log -1 --format=%s)"
fi
rm -f "$COMMIT_MSG_FILE"

# 创建版本标签（TAG 已在「版本管理」段计算）
if ! git tag -l "$TAG" | grep -q "$TAG"; then
    run git tag -a "$TAG" -m "Release $TAG - $BUILD_TIME"
    if [ "$DRY_RUN" != "1" ]; then echo "   已创建标签: $TAG"; fi
else
    echo "   标签 $TAG 已存在，跳过创建"
fi

# 推送到远程
if [ "$DRY_RUN" = "1" ] || [ "$SKIP_PUSH" = "1" ]; then
    echo "   跳过推送（DRY_RUN=$DRY_RUN SKIP_PUSH=$SKIP_PUSH）"
else
    echo "   推送到 GitHub..."
    CURRENT_BRANCH=$(git branch --show-current)
    if [ -z "$CURRENT_BRANCH" ]; then CURRENT_BRANCH="master"; fi

    git push origin "$CURRENT_BRANCH" 2>&1 && echo "   ✅ 代码已推送" || echo "   ⚠️ 推送失败，请手动执行: git push origin $CURRENT_BRANCH"
    git push origin "$TAG" 2>&1 && echo "   ✅ 标签已推送" || echo "   ⚠️ 标签推送失败，请手动执行: git push origin $TAG"
fi

# ============ GitHub Release ============
echo ""
echo "🚀 GitHub Release..."

if [ "$DRY_RUN" = "1" ] || [ "$SKIP_PUSH" = "1" ]; then
    echo "   跳过 Release 创建（DRY_RUN=$DRY_RUN SKIP_PUSH=$SKIP_PUSH）"
elif ! command -v gh &>/dev/null; then
    echo "   ⚠️ gh CLI 未安装，跳过自动 Release"
    echo "   请手动创建: $GITHUB_RELEASES/new?tag=$TAG"
elif gh release view "$TAG" --repo Mr-Sure/CopyList &>/dev/null; then
    echo "   Release $TAG 已存在，跳过创建"
elif [ "$HAS_CHANGES" != true ]; then
    echo "   无代码变更，跳过 Release 创建"
else
    # Release 说明 = CHANGELOG 条目正文（与 commit message 同源）+ 构建信息
    RELEASE_NOTES_FILE="/tmp/copylist_release_notes.md"
    cat > "$RELEASE_NOTES_FILE" << EOF
## 🎉 CopyList $TAG

${CHANGELOG_BODY}

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

- [📖 完整更新日志]($GITHUB_RELEASES/tag/$TAG)
- [🐛 问题反馈](https://github.com/Mr-Sure/CopyList/issues)
- [💬 公众号](https://raw.githubusercontent.com/Mr-Sure/CopyList/master/Docs/wechat_qrcode.jpg)

---

**如果觉得好用，请给个 ⭐ Star 支持一下！**
EOF

    echo "   创建 Release $TAG..."
    if gh release create "$TAG" \
        --repo Mr-Sure/CopyList \
        --title "CopyList $TAG" \
        --notes-file "$RELEASE_NOTES_FILE" \
        CopyList.dmg 2>&1; then
        echo "   ✅ Release 已创建并上传 DMG"
    else
        echo "   ⚠️ Release 创建失败，请手动创建: $GITHUB_RELEASES/new?tag=$TAG"
    fi

    rm -f "$RELEASE_NOTES_FILE"
fi

# ============ 完成 ============
echo ""
if [ "$DRY_RUN" = "1" ]; then
    echo "=========================================="
    echo "  🧪 DRY-RUN 结束：未修改任何文件、未编译、未推送"
    echo "  将要发布的版本: v${NEW_VERSION} (build ${BUILD_NUMBER})"
    echo "  commit 标题: release(${TAG}): ${COMMIT_SUBJECT}"
    echo "  确认文案无误后执行: bash Scripts/build.sh"
    echo "=========================================="
    exit 0
fi

echo "=========================================="
echo "  ✅ CopyList v${NEW_VERSION} 构建完成！"
echo "  📅 构建时间: $BUILD_TIME"
echo "  📦 DMG: $(pwd)/CopyList.dmg"
echo "  🏷️  标签: $TAG"
echo "  🌐 Release: $GITHUB_RELEASES/tag/$TAG"
echo "=========================================="
echo ""
echo "📋 发布后校验（详见 Docs/发布流程.md 第八节）："
echo "  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/CopyList.app/Contents/Info.plist"
echo "  gh release view $TAG --repo Mr-Sure/CopyList"
