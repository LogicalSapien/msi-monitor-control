#!/usr/bin/env bash
#
# build-app.sh — assemble an unsigned MSIMonitorControl.app bundle.
#
# Phase 1: unsigned, build-and-run from source. No signing or notarisation
# (that is Phase 2). On first launch Gatekeeper may warn — right-click the
# .app and choose Open to allow it.
#
# Usage:
#   ./build-app.sh
#   open build/MSIMonitorControl.app
#
set -euo pipefail

# Always operate relative to this script's directory (the macos/ folder).
cd "$(dirname "$0")"

readonly BINARY_NAME="MSIControlApp"          # the SwiftPM executable target
readonly APP_NAME="MSIMonitorControl"
readonly APP_DIR="build/${APP_NAME}.app"
readonly INFO_PLIST="Sources/MSIControlApp/Info.plist"

echo "==> Building release binary…"
swift build -c release

readonly RELEASE_BIN=".build/release/${BINARY_NAME}"
if [[ ! -x "${RELEASE_BIN}" ]]; then
    echo "error: release binary not found at ${RELEASE_BIN}" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Standard bundle layout: binary in Contents/MacOS, plist in Contents.
cp "${RELEASE_BIN}" "${APP_DIR}/Contents/MacOS/${BINARY_NAME}"
cp "${INFO_PLIST}"  "${APP_DIR}/Contents/Info.plist"

# Sanity check: CFBundleExecutable must match the copied binary name.
plist_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_DIR}/Contents/Info.plist")"
if [[ "${plist_exec}" != "${BINARY_NAME}" ]]; then
    echo "error: CFBundleExecutable (${plist_exec}) does not match binary (${BINARY_NAME})" >&2
    exit 1
fi

echo ""
echo "==> Built: $(pwd)/${APP_DIR}"
echo "    To run: open macos/build/${APP_NAME}.app"
