#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MouseJumpUtility"
APP_BUNDLE="${APP_NAME}.app"
EXECUTABLE_PATH="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
INFO_PLIST="${APP_BUNDLE}/Contents/Info.plist"
ZIP_NAME="${APP_NAME}.zip"
BUNDLE_ID="com.fruitjuice088.${APP_NAME}"
VERSION="1.0"

log() {
    echo "[build] $*"
}

log "Cleaning previous output..."
rm -rf "${APP_BUNDLE}" build "${ZIP_NAME}"

log "Creating bundle structure..."
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/AppIcon.iconset"

log "Compiling sources..."
swiftc -O -o "${EXECUTABLE_PATH}" "${APP_NAME}.swift"
chmod +x "${EXECUTABLE_PATH}"

log "Configuring Info.plist..."
cp Info.plist "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${INFO_PLIST}"

log "Creating ${ZIP_NAME}..."
zip -qry "${ZIP_NAME}" "${APP_BUNDLE}"

log "Build complete. Launch with: open ${APP_BUNDLE}"
log "Distributable archive created: ${ZIP_NAME}"
