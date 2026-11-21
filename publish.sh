#!/bin/bash
# 生成安装包并上传到 GitHub / Build the installer and publish to GitHub
#
#   bash publish.sh
#
# 1. 如果还没有安装包，先运行 package.sh
# 2. 提交源码并推送到 https://github.com/bodyzxy/Lumen （main 分支）
#    安装包不放进代码仓库，只放在 GitHub Release 里
# 3. 如果装了并登录了 GitHub CLI（gh），自动创建 / 更新 Release 并附上安装包
set -euo pipefail
cd "$(dirname "$0")"

REMOTE="https://github.com/bodyzxy/Lumen.git"
REPO="bodyzxy/Lumen"
VERSION="1.0.0"
PKG_NAME="Lumen-${VERSION}.pkg"

chmod +x run.sh package.sh publish.sh 2>/dev/null || true
rm -f README.zh-CN.md

if [ ! -f "dist/${PKG_NAME}" ]; then
    bash package.sh
fi

if [ ! -d .git ]; then
    git init -q
fi
git branch -M main 2>/dev/null || true
if [ -z "$(git config user.name || true)" ]; then git config user.name "bodyzxy"; fi
if [ -z "$(git config user.email || true)" ]; then git config user.email "bodyzxy@users.noreply.github.com"; fi
if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "${REMOTE}"
else
    git remote add origin "${REMOTE}"
fi

# 安装包只放在 Release 里：把之前提交进仓库的 release/ 移出版本控制
if git ls-files --error-unmatch release >/dev/null 2>&1; then
    git rm -r -q --cached release
fi
rm -rf release

echo "▸ 提交 / Committing…"
git add -A
if ! git diff --cached --quiet; then
    git commit -q -F - <<'MSG'
Ship Lumen as a macOS installer (.pkg)

- package.sh now builds dist/Lumen-<version>.pkg with an install wizard
- Apple silicon build, installs into /Applications
- Installers live in GitHub Releases instead of the repository

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01XM8LaF8oMsNudVbLwW4xLk
MSG
fi

echo "▸ 同步远程 / Syncing with GitHub…"
if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
    git fetch -q origin main
    if ! git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
        git merge -q --no-edit --allow-unrelated-histories -X ours origin/main -m "Merge existing GitHub history"
    fi
fi

echo "▸ 推送 / Pushing to ${REMOTE}…"
git push -u origin main

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "▸ 更新 Release / Updating GitHub release v${VERSION}…"
    if gh release view "v${VERSION}" --repo "${REPO}" >/dev/null 2>&1; then
        gh release upload "v${VERSION}" "dist/${PKG_NAME}" --clobber --repo "${REPO}"
        gh release delete-asset "v${VERSION}" "Lumen-${VERSION}-macOS.zip" --yes --repo "${REPO}" 2>/dev/null || true
        gh release edit "v${VERSION}" --notes-file RELEASE_NOTES.md --repo "${REPO}"
    else
        gh release create "v${VERSION}" "dist/${PKG_NAME}" --repo "${REPO}" \
            --title "Lumen ${VERSION}" --notes-file RELEASE_NOTES.md
    fi
    echo "✓ 已发布 / Published: https://github.com/${REPO}/releases/tag/v${VERSION}"
else
    echo ""
    echo "✓ 源码已推送 / Source pushed: https://github.com/${REPO}"
    echo "  接下来请在 GitHub 的 Release 页面上传安装包：dist/${PKG_NAME}"
    echo "  Next, upload the installer to the GitHub release: dist/${PKG_NAME}"
fi
