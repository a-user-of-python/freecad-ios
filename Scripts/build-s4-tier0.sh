#!/bin/bash
# Spike S4 Tier 0 — gl4es static iOS build + one QOpenGLWidget + lit
# fixed-function triangle on Qt's EAGL context, read back in-app.
# Builds for iOS Simulator (runs there, screenshot + readback captured)
# and for device arm64 (build-verified, lipo + strings checks).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/build-s4-lib.sh"

OUT="$S4_ROOT/dist-s4/tier0"
rm -rf "$OUT"; mkdir -p "$OUT"
exec > >(tee "$OUT/tier0-build.log") 2>&1

install_qt
fetch_gl4es
build_gl4es device
build_gl4es sim
build_gl4es_applefix device
build_gl4es_applefix sim

echo "== building Tier0 app (device arm64)"
configure_app "$S4_ROOT/Spike/S4/Tier0" "$S4_WORK/tier0-device" device
cmake --build "$S4_WORK/tier0-device" -j3
APP_DEV="$S4_WORK/tier0-device/S4Tier0.app"
test -d "$APP_DEV"
lipo -info "$APP_DEV/S4Tier0" | tee "$OUT/device-lipo.txt"
grep -q arm64 "$OUT/device-lipo.txt"
strings "$APP_DEV/S4Tier0" > "$S4_WORK/tier0-strings.txt"
grep -q QIOSIntegration "$S4_WORK/tier0-strings.txt" && echo "device: QIOSIntegration linked"
tar -cf "$OUT/S4Tier0-device-app.tar" -C "$S4_WORK/tier0-device" S4Tier0.app

echo "== building Tier0 app (simulator)"
configure_app "$S4_ROOT/Spike/S4/Tier0" "$S4_WORK/tier0-sim" sim
cmake --build "$S4_WORK/tier0-sim" -j3
APP_SIM="$S4_WORK/tier0-sim/S4Tier0.app"
test -d "$APP_SIM"
lipo -info "$APP_SIM/S4Tier0"

echo "== running Tier0 in iOS Simulator (SIMULATOR evidence)"
run_in_simulator "$APP_SIM" "com.user.freecad.s4tier0" "s4_tier0_result.txt" "$OUT/sim"

if [ -f "$OUT/sim/simulator-screenshot.png" ]; then
	python3 "$S4_ROOT/Spike/S4/tools/png_stats.py" "$OUT/sim/simulator-screenshot.png" \
		> "$OUT/sim/screenshot-stats.json" || true
	cat "$OUT/sim/screenshot-stats.json" || true
fi

echo "== Tier0 verdict inputs:"
cat "$OUT/sim/s4_tier0_result.txt" 2>/dev/null || echo "NO RESULT FILE — see app-console.log"
echo "== tier0 script done"
