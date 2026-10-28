#!/usr/bin/env bash
# ==============================================================================
# package-app.sh — CoreScope Native macOS App Packager
#
# Builds the CoreScope executable in Release mode using Swift Package Manager,
# creates a standard macOS application bundle (CoreScope.app), generates a clean
# Info.plist, applies ad-hoc code signature for local execution, and creates an
# optional ZIP distribution archive.
#
# Customization via Environment Variables:
#   BUNDLE_ID    : Bundle identifier (default: com.shrihaan.corescope)
#   APP_VERSION  : Marketing version string (default: 1.0.0)
#   BUILD_NUMBER : Internal build version (default: 1)
#   OUTPUT_DIR   : Destination directory for artifacts (default: build)
#   ICON_PATH    : Path to valid .icns file, if one exists (default: none)
#
# Example Usage:
#   ./scripts/package-app.sh
#   BUNDLE_ID=io.custom.corescope APP_VERSION=1.1.0 ./scripts/package-app.sh
# ==============================================================================

set -euo pipefail

# 1. Resolve repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# 2. Configuration parameters
BUNDLE_ID="${BUNDLE_ID:-com.shrihaan.corescope}"
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
ICON_PATH="${ICON_PATH:-}"

APP_NAME="CoreScope"
BUNDLE_DIR="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}-${APP_VERSION}.zip"

echo "======================================================================"
echo " Packaging ${APP_NAME} v${APP_VERSION} (${BUNDLE_ID})"
echo "======================================================================"

# 3. Clean previous build artifacts
echo "==> Cleaning destination directory: ${OUTPUT_DIR}"
rm -rf "${BUNDLE_DIR}" "${ZIP_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 4. Build in Release configuration with Swift Package Manager
echo "==> Compiling CoreScope in Release configuration (swift build -c release)..."
swift build -c release

RELEASE_BIN="${REPO_ROOT}/.build/release/${APP_NAME}"
if [[ ! -f "${RELEASE_BIN}" ]]; then
    echo "ERROR: Compiled executable not found at ${RELEASE_BIN}" >&2
    exit 1
fi

# 5. Copy executable into bundle
echo "==> Copying executable into ${MACOS_DIR}/${APP_NAME}..."
cp "${RELEASE_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod 755 "${MACOS_DIR}/${APP_NAME}"

# 6. Generate PkgInfo
echo "==> Writing PkgInfo..."
printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# 7. Check for optional app icon
ICON_PLIST_ENTRY=""
if [[ -n "${ICON_PATH}" && -f "${ICON_PATH}" ]]; then
    echo "==> Valid icon provided at ${ICON_PATH}. Copying to Resources..."
    cp "${ICON_PATH}" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_PLIST_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
elif [[ -f "${REPO_ROOT}/Resources/AppIcon.icns" ]]; then
    echo "==> Found existing icon at Resources/AppIcon.icns. Copying..."
    cp "${REPO_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_PLIST_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    echo "==> No icon asset found or provided. Omitting CFBundleIconFile entry."
fi

# 7b. Bundle local ambient background image
AMBIENT_SRC="${REPO_ROOT}/Sources/CoreScope/Resources/CoreScopeAmbient.png"
if [[ -f "${AMBIENT_SRC}" ]]; then
    echo "==> Bundling CoreScopeAmbient.png into ${RESOURCES_DIR}/CoreScopeAmbient.png..."
    cp "${AMBIENT_SRC}" "${RESOURCES_DIR}/CoreScopeAmbient.png"
else
    echo "==> Note: CoreScopeAmbient.png not found at ${AMBIENT_SRC}; skipping image bundling."
fi

# 8. Generate Info.plist
echo "==> Generating Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 CoreScope Contributors. MIT License.</string>
${ICON_PLIST_ENTRY}
</dict>
</plist>
EOF

# 9. Apply ad-hoc signature for local execution
# Note: Ad-hoc signing seals the bundle code integrity for macOS Gatekeeper
# local execution. It does NOT provide Apple Developer ID signing or notarization.
echo "==> Applying ad-hoc code signature (codesign --sign -)..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

# 10. Verify code signature
echo "==> Verifying bundle signature..."
codesign --verify --deep --strict --verbose=2 "${BUNDLE_DIR}"

# 11. Create clean ZIP distribution archive
echo "==> Creating ZIP archive: ${ZIP_PATH}..."
rm -f "${ZIP_PATH}"
(cd "${OUTPUT_DIR}" && zip -qry -X "${APP_NAME}-${APP_VERSION}.zip" "${APP_NAME}.app")

# 12. Bundle inspection report
echo ""
echo "======================================================================"
echo " Bundle Summary"
echo "======================================================================"
echo "Bundle Location: ${BUNDLE_DIR}"
echo "ZIP Archive:     ${ZIP_PATH}"
echo "Binary Size:     $(ls -lh "${MACOS_DIR}/${APP_NAME}" | awk '{print $5}')"
echo "Bundle Size:     $(du -sh "${BUNDLE_DIR}" | awk '{print $1}')"
echo "Architecture:    $(file "${MACOS_DIR}/${APP_NAME}" | cut -d: -f2-)"
echo ""
echo "Bundle File Tree:"
find "${BUNDLE_DIR}" -print | sed -e "s;${BUNDLE_DIR};CoreScope.app;"
echo ""
echo "Ad-Hoc Signing Details:"
codesign -dvvv "${BUNDLE_DIR}" 2>&1 | grep -E "Signature|Identifier|Format|CodeDirectory|Authority" || true
echo "======================================================================"
echo " Packaging completed successfully."
echo "======================================================================"
