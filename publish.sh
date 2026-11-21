#!/bin/bash
# 打包并上传到 GitHub / Package and publish to GitHub
#
#   bash publish.sh
#
# 1. 如果还没打包，先运行 package.sh
# 2. 把打好的 zip 放进 release/ 一起提交
# 3. 推送到 https://github.com/bodyzxy/Lumen （main 分支）
# 4. 如果装了并登录了 GitHub CLI（gh），再顺便创建一个 Release 并附上 zip
set -euo pipefail
cd "$(dirname "$0")"

REMOTE="https://github.com/bodyzxy/Lumen.git"
VERSION="1.0.0"
ZIP_NAME="Lumen-${VERSION}-macOS.zip"

chmod +x run.sh package.sh publish.sh 2>/dev/null || true
# 中文说明已经合并进 README.md
rm -f README.zh-CN.md

if [ ! -f "dist/${ZIP_NAME}" ]; then
    bash package.sh
fi

echo "▸ 准备发布文件 / Preparing release files…"
mkdir -p release
cp "dist/${ZIP_NAME}" "release/${ZIP_NAME}"

if [ ! -d .git ]; then
    git init -q
fi
git branch -M main 2>/dev/null || true

# 没设置过 Git 身份时，只给这个仓库设置一个
if [ -z "$(git config user.name || true)" ]; then
    git config user.name "bodyzxy"
fi
if [ -z "$(git config user.email || true)" ]; then
    git config user.email "bodyzxy@users.noreply.github.com"
fi

if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${REMOTE}"
else
    git remote add origin "${REMOTE}"
fi

echo "▸ 提交 / Committing…"
git add -A
if ! git diff --cached --quiet; then
    git commit -q -F - <<'MSG'
Lumen 1.0.0 — a lightweight Mac app for editing and color-grading photos

- Every color adjustment from Photoshop's Image › Adjustments menu, plus HSL and color grading
- Non-destructive adjustment layers, rendered on the GPU through 3D LUTs
- Multiple photos with a filmstrip, reusable adjustments, presets and .cube export
- Light monochrome interface, English / 简体中文
- Packaged app: release/Lumen-1.0.0-macOS.zip

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XM8LaF8oMsNudVbLwW4xLk
MSG
fi

# 如果 GitHub 上已经有内容（比如之前推过只有 “# Lumen” 的 README），先合并进来，冲突时以本地为准
echo "▸ 同步远程 / Syncing with GitHub…"
if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git fetch -q origin main
    if ! git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
        git merge -q --no-edit --allow-unrelated-histories -X ours origin/main \
            -m "Merge existing GitHub history"
    fi
fi

echo "▸ 推送 / Pushing to ${REMOTE}…"
git push -u origin main

# 可选：用 GitHub CLI 创建 Release
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "▸ 创建 Release / Creating GitHub release v${VERSION}…"
    if gh release view "v${VERSION}" --repo bodyzxy/Lumen >/dev/null 2>&1; then
        gh release upload "v${VERSION}" "release/${ZIP_NAME}" --clobber --repo bodyzxy/Lumen
    else
        gh release create "v${VERSION}" "release/${ZIP_NAME}" --repo bodyzxy/Lumen \
            --title "Lumen ${VERSION}" --notes-file RELEASE_NOTES.md
    fi
else
    echo "  （没有检测到已登录的 gh 命令行工具，跳过创建 Release；安装包已经在仓库的 release/ 文件夹里）"
    echo "  (GitHub CLI not found or not logged in — skipped the Release. The app is in the repo's release/ folder.)"
fi

echo ""
echo "✓ 已发布 / Published: https://github.com/bodyzxy/Lumen"
