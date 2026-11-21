#!/bin/bash
# 打包 Lumen.app / Package Lumen.app
#
#   bash package.sh
#
# 产物 / Output:
#   dist/Lumen.app
#   dist/Lumen-<version>-macOS.zip
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Lumen"
VERSION="1.0.0"
BUILD_NUMBER="1"
BUNDLE_ID="com.bodyzxy.lumen"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"
ZIP="${DIST}/${APP_NAME}-${VERSION}-macOS.zip"

# 装了 Xcode 就用 Xcode 的工具链（才能编出同时支持 Apple 芯片和 Intel 的通用版本）
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "▸ 编译 Release / Building release…"
ARCH_FLAGS="--arch arm64 --arch x86_64"
if swift build -c release ${ARCH_FLAGS}; then
    ARCH_DESC="Universal (Apple silicon + Intel)"
else
    echo "  通用版本编译失败，改为只编译本机架构 / Universal build failed, building for this Mac only"
    ARCH_FLAGS=""
    swift build -c release
    ARCH_DESC="$(uname -m)"
fi
BIN_DIR="$(swift build -c release ${ARCH_FLAGS} --show-bin-path)"

echo "▸ 组装 .app / Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Packaging/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
strip -x "${APP}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 bodyzxy</string>
</dict>
</plist>
PLIST

echo "▸ 本机签名 / Ad-hoc signing…"
codesign --force --deep --sign - "${APP}"
codesign --verify --verbose=1 "${APP}"

echo "▸ 压缩 / Zipping…"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

MINOS="$(vtool -show-build "${APP}/Contents/MacOS/${APP_NAME}" 2>/dev/null | awk '/minos/ {print $2; exit}' || true)"
APP_SIZE="$(du -sh "${APP}" | cut -f1)"
ZIP_SIZE="$(du -sh "${ZIP}" | cut -f1)"
echo ""
echo "✓ 完成 / Done"
echo "  App:  ${APP}  (${APP_SIZE}, ${ARCH_DESC}, macOS ${MINOS:-?}+)"
echo "  Zip:  ${ZIP}  (${ZIP_SIZE})"
echo ""
echo "  双击 dist/Lumen.app 即可运行，也可以把它拖进“应用程序”文件夹。"
echo "  Double-click dist/Lumen.app to run, or drag it into Applications."
