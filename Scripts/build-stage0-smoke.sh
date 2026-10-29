#!/bin/bash
# S0 — Toolchain smoke (REAL stage).
#
# FEBio's Stage-0 recipe adapted (front 06 Stage 0; front 05 P4):
# aqtinstall Qt 6.9.3 (fallback 6.8.3) — desktop clang_64 kit for
# host tools + iOS kit for the target, --modules qtshadertools —
# then build the minimal Qt Widgets app in Spike/S0-smoke/ with the
# iOS kit's qt.toolchain.cmake + QT_HOST_PATH=<desktop kit>, verify
# the binary (arm64; strings show QIOSIntegration), and write the
# report into dist-smoke/. Nothing about FreeCAD is forced here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/stage0"
SRC="$ROOT/Spike/S0-smoke"
BLD="$WORK/build"
DIST="$ROOT/dist-smoke"
mkdir -p "$WORK" "$DIST"

# shellcheck source=qt-install.inc.sh
. "$ROOT/Scripts/qt-install.inc.sh"

echo "== Qt host-path machinery (from the installed kits):"
grep -n "QT_HOST_PATH" "$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" | head -20 || true

# CMAKE_OSX_SYSROOT: resolved SDK path from qt-install.inc.sh
# (CMake 4.x fatals on the "iphoneos" name; xcrun is unreliable on
# some runners — see the include for the discovery logic).

# Try the flag variants in order, FEBio-style: the first that
# configures wins and is used for the build.
QT_FLAGS_MODE=""
if cmake -S "$SRC" -B "$BLD" -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" \
	-DQT_HOST_PATH="$QT_DESKTOP" \
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH" \
	-DCMAKE_PREFIX_PATH="$QT_IOS" \
	-DQt6_DIR="$QT_IOS/lib/cmake/Qt6" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 >"$WORK/logA.txt" 2>&1; then
	QT_FLAGS_MODE="A"
	echo "== smoke configure: variant A (toolchain + QT_HOST_PATH + prefix + Qt6_DIR) OK"
elif cmake -S "$SRC" -B "$BLD" -G Ninja \
	-DCMAKE_TOOLCHAIN_FILE="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" \
	-DQT_HOST_PATH="$QT_DESKTOP" \
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 >"$WORK/logB.txt" 2>&1; then
	QT_FLAGS_MODE="B"
	echo "== smoke configure: variant B (toolchain + QT_HOST_PATH only) OK"
else
	echo "ERROR: smoke configure failed for both flag variants" >&2
	echo "----- variant A log:" >&2; cat "$WORK/logA.txt" >&2
	echo "----- variant B log:" >&2; cat "$WORK/logB.txt" >&2 || true
	exit 1
fi

echo "== building S0 smoke app"
cmake --build "$BLD" -j"$(sysctl -n hw.ncpu)"

BIN="$(find "$BLD" -type f -name "s0-smoke" -perm -u+x | head -1)"
if [ -z "$BIN" ]; then
	BIN="$(find "$BLD" -path "*s0-smoke.app/s0-smoke" -type f | head -1)"
fi
test -n "$BIN" && test -f "$BIN"
echo "== smoke binary: $BIN"

echo "== verifying the smoke binary"
file "$BIN" | tee "$WORK/file.txt"
lipo -info "$BIN" | tee "$WORK/lipo.txt"
grep -q "arm64" "$WORK/lipo.txt" || { echo "ERROR: binary is not arm64" >&2; exit 1; }
# strings into a file first (FEBio run 40805198400 SIGPIPE lesson).
strings "$BIN" > "$WORK/binary-strings.txt"
if grep -q "QIOSIntegration" "$WORK/binary-strings.txt"; then
	echo "   Qt iOS platform plugin: linked (QIOSIntegration)"
else
	echo "ERROR: QIOSIntegration not found — Qt iOS platform plugin did not link" >&2
	exit 1
fi

{
	echo "S0 toolchain smoke — report"
	echo "Qt version installed: $QT_VERSION"
	echo "Qt iOS kit: $QT_IOS"
	echo "Qt desktop (host) kit: $QT_DESKTOP"
	echo "Configure flag variant: $QT_FLAGS_MODE"
	echo "iOS SDK (CMAKE_OSX_SYSROOT): $IOS_SDK_PATH"
	echo "Smoke source: Spike/S0-smoke (QApplication + QWidget, qt_add_executable)"
	echo "Binary: $BIN"
	echo "file: $(cat "$WORK/file.txt")"
	echo "lipo: $(cat "$WORK/lipo.txt")"
	echo "QIOSIntegration: present (strings)"
	ls -lh "$BIN"
} | tee "$DIST/report.txt"
echo "== S0 done"
