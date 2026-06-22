#!/usr/bin/env bash
#
# build-app.sh — assemble an ad-hoc-signed MSIMonitorControl.app bundle.
#
# Phase 1: no Developer ID signing or notarisation (that is Phase 2). The bundle
# IS ad-hoc signed (codesign --sign -) so the signature seals the assembled
# bundle — without this seal macOS reports "MSIMonitorControl is damaged and
# can't be opened" on a downloaded copy. On first launch Gatekeeper may still
# warn (no Developer ID); right-click → Open, or strip the quarantine flag:
#   xattr -dr com.apple.quarantine build/MSIMonitorControl.app
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
readonly ICON_SRC="../assets/icon.icns"       # produced by the logo asset set
readonly ICON_DEST_NAME="icon.icns"           # must match CFBundleIconFile

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

# Embed the app icon if the asset set has landed (CFBundleIconFile is already
# set in Info.plist). Until assets/icon.icns is committed this is skipped and
# the app uses the default icon.
if [[ -f "${ICON_SRC}" ]]; then
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/${ICON_DEST_NAME}"
    echo "==> Embedded icon: ${ICON_SRC}"
else
    echo "==> Icon ${ICON_SRC} not found yet — using default icon (will embed once committed)."
fi

# Sanity check: CFBundleExecutable must match the copied binary name.
plist_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_DIR}/Contents/Info.plist")"
if [[ "${plist_exec}" != "${BINARY_NAME}" ]]; then
    echo "error: CFBundleExecutable (${plist_exec}) does not match binary (${BINARY_NAME})" >&2
    exit 1
fi

# Ad-hoc sign so the signature SEALS the assembled bundle. Without this the
# linker's adhoc binary signature does not cover the bundle (Info.plist=not
# bound, Sealed Resources=none) and a downloaded copy is reported as "damaged".
#
# NOTE on `--deep`: it is deprecated since Xcode 13. It is acceptable HERE because
# this is a flat, single-executable bundle (one Mach-O in Contents/MacOS, no
# nested frameworks/helpers/XPC services) — there is nothing inner for `--deep` to
# mis-sign. If a nested framework, helper tool, or XPC service is ever added,
# STOP using `--deep` and sign explicitly inner-first then outer-last
# (sign each nested code object, then the outer .app).
echo "==> Ad-hoc signing (seals the bundle)…"
codesign --force --deep --sign - "${APP_DIR}"

# Verify the seal really took. The `codesign --verify --deep --strict` EXIT CODE
# is the authoritative gate (set -e aborts the build on any non-zero exit); the
# `codesign -dv` line below is purely informational.
echo "==> Verifying signature (exit code is the gate)…"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

echo "==> Signature summary (informational):"
codesign -dv "${APP_DIR}" 2>&1 | grep -E "Signature|Sealed Resources|Info.plist" || true

echo ""
echo "==> Built: $(pwd)/${APP_DIR}"
echo "    To run: open macos/build/${APP_NAME}.app"
