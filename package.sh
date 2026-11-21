#!/bin/bash
# 生成 Lumen 安装包 / Build the Lumen installer
#
#   bash package.sh
#
# 产物 / Output:
#   dist/Lumen-<version>.pkg     安装包：双击后按向导把 Lumen 装进“应用程序”
#                                Installer: double-click and follow the steps to install Lumen into Applications
#   dist/Lumen.app               （中间产物 / intermediate build）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Lumen"
VERSION="1.0.0"
BUILD_NUMBER="1"
BUNDLE_ID="com.bodyzxy.lumen"
DIST="dist"
WORK="${DIST}/.work"
APP="${DIST}/${APP_NAME}.app"
PKG="${DIST}/${APP_NAME}-${VERSION}.pkg"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
# 保证在 macOS 14 及以上都能运行
export MACOSX_DEPLOYMENT_TARGET=14.0

# ---------------------------------------------------------------- 1. 编译
echo "▸ 编译 Release（Apple 芯片）/ Building release for Apple silicon…"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

# ---------------------------------------------------------------- 2. 组装 .app
echo "▸ 组装 ${APP_NAME}.app / Assembling the app…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
chmod 755 "${APP}/Contents/MacOS/${APP_NAME}"
cp "Packaging/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"

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
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
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

# 清掉可能混进来的扩展属性，再做本机签名
xattr -cr "${APP}"
codesign --force --sign - --timestamp=none "${APP}"
codesign --verify --strict "${APP}"

# 打包前先确认程序本身能正常启动（启动 3 秒后自动关掉）
echo "▸ 试运行 / Smoke test…"
"${APP}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 &
TEST_PID=$!
sleep 3
if kill -0 "${TEST_PID}" 2>/dev/null; then
    kill "${TEST_PID}" 2>/dev/null || true
    wait "${TEST_PID}" 2>/dev/null || true
    echo "  ✓ 程序可以正常启动 / The app launches"
else
    echo "  ✗ 程序启动后立即退出了，请把下面的输出发给开发者 / The app exited immediately:"
    "${APP}/Contents/MacOS/${APP_NAME}" || true
    exit 1
fi

# ---------------------------------------------------------------- 3. 生成安装包
echo "▸ 生成安装包 / Building the installer…"
rm -rf "${WORK}"
mkdir -p "${WORK}/root/Applications" "${WORK}/resources"
ditto "${APP}" "${WORK}/root/Applications/${APP_NAME}.app"

# 组件描述：禁止“重定位”，保证一定装到 /Applications，而不是去覆盖电脑上别处的同名 App
pkgbuild --analyze --root "${WORK}/root" "${WORK}/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "${WORK}/component.plist"
plutil -replace 0.BundleOverwriteAction -string upgrade "${WORK}/component.plist"

pkgbuild \
    --root "${WORK}/root" \
    --component-plist "${WORK}/component.plist" \
    --identifier "${BUNDLE_ID}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${WORK}/${APP_NAME}-component.pkg" >/dev/null

# 安装向导的欢迎页、完成页和背景
cp Packaging/installer/welcome.html Packaging/installer/conclusion.html "${WORK}/resources/"
tiffutil -cathidpicheck Packaging/installer/background.png Packaging/installer/background@2x.png \
    -out "${WORK}/resources/background.tiff" >/dev/null 2>&1 \
    || cp Packaging/installer/background.png "${WORK}/resources/background.tiff"

cat > "${WORK}/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>${APP_NAME} ${VERSION}</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <background file="background.tiff" alignment="bottomleft" scaling="none"/>
    <background-darkAqua file="background.tiff" alignment="bottomleft" scaling="none"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="14.0"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="${BUNDLE_ID}"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="${BUNDLE_ID}" visible="false">
        <pkg-ref id="${BUNDLE_ID}"/>
    </choice>
    <pkg-ref id="${BUNDLE_ID}" version="${VERSION}" onConclusion="none">${APP_NAME}-component.pkg</pkg-ref>
</installer-gui-script>
XML

rm -f "${PKG}"
productbuild \
    --distribution "${WORK}/distribution.xml" \
    --resources "${WORK}/resources" \
    --package-path "${WORK}" \
    "${PKG}" >/dev/null
rm -rf "${WORK}"

PKG_SIZE="$(du -sh "${PKG}" | cut -f1)"
echo ""
echo "✓ 完成 / Done"
echo "  安装包 / Installer:  ${PKG}  (${PKG_SIZE})"
echo ""
echo "  把这个 .pkg 上传到 GitHub Release，用户下载后双击，按向导安装即可。"
echo "  Upload this .pkg to the GitHub release. Users double-click it and follow the steps."
