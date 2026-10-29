#!/bin/bash
# Spike S4 Tier 1 — unmodified Coin 4.0.10 + companion GLU against
# gl4es; FreeCAD's vendored QuarterWidget (pinned weekly-2026.09.16,
# sha256-verified download) rendering HelloCone; simulator run +
# screenshot; analytic ground-truth reference for pixel statistics.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/build-s4-lib.sh"

OUT="$S4_ROOT/dist-s4/tier1"
rm -rf "$OUT"; mkdir -p "$OUT"
exec > >(tee "$OUT/tier1-build.log") 2>&1

install_qt
fetch_gl4es

echo "== fetching pinned FreeCAD weekly tarball (for vendored Quarter)"
FC_TARBALL="$S4_WORK/freecad_source_weekly-2026.09.16.tar.gz"
if [ ! -f "$FC_TARBALL" ]; then
	curl -sfL -o "$FC_TARBALL" \
		"https://github.com/FreeCAD/FreeCAD/releases/download/weekly-2026.09.16/freecad_source_weekly-2026.09.16.tar.gz"
fi
echo "1fba830dbb58c67c88222b375d336e721f03e728cdb0392b4080f6ef02fea0c4  $FC_TARBALL" | shasum -a 256 -c -
FC_SRC="$S4_WORK/freecad-weekly"
if [ ! -d "$FC_SRC/src/Gui/Quarter" ]; then
	rm -rf "$FC_SRC"; mkdir -p "$FC_SRC"
	tar -xzf "$FC_TARBALL" -C "$FC_SRC" src/Gui/Quarter \
		src/Gui/Inventor/SoMouseWheelEvent.h src/Gui/Inventor/SoMouseWheelEvent.cpp
fi
ls "$FC_SRC/src/Gui/Quarter" | head
# vendored-coin version note for the verdict (submodule src/3rdParty/coin)
tar -xzOf "$FC_TARBALL" src/3rdParty/coin/CMakeLists.txt 2>/dev/null | grep -m3 -E "COIN_(MAJOR|MINOR|MICRO)_VERSION" \
	| tee "$OUT/vendored-coin-version.txt" || true

fetch_coin

for arch in device sim; do
	build_gl4es "$arch"
	build_gl4es_applefix "$arch"
	build_glu "$arch"
	build_coin "$arch"
done

echo "== ground-truth reference render (analytic, same scene)"
python3 "$S4_ROOT/Spike/S4/tools/cone_reference.py" "$OUT/cone-reference.png" \
	> "$OUT/cone-reference-stats.json"
cat "$OUT/cone-reference-stats.json"
python3 "$S4_ROOT/Spike/S4/tools/png_stats.py" "$OUT/cone-reference.png" \
	> "$OUT/cone-reference-stats-png.json" || true

echo "== building Tier1 app (device arm64)"
configure_app "$S4_ROOT/Spike/S4/Tier1" "$S4_WORK/tier1-device" device -DFREECAD_SRC_DIR="$FC_SRC"
cmake --build "$S4_WORK/tier1-device" -j3 2>&1 | tee "$OUT/tier1-device-build.log"
APP_DEV="$S4_WORK/tier1-device/S4Tier1.app"
test -d "$APP_DEV"
lipo -info "$APP_DEV/S4Tier1" | tee "$OUT/device-lipo.txt"
grep -q arm64 "$OUT/device-lipo.txt"
strings "$APP_DEV/S4Tier1" > "$S4_WORK/tier1-strings.txt"
grep -q QIOSIntegration "$S4_WORK/tier1-strings.txt" && echo "device: QIOSIntegration linked"
grep -q "QuarterWidget" "$S4_WORK/tier1-strings.txt" && echo "device: QuarterWidget present in binary"
tar -cf "$OUT/S4Tier1-device-app.tar" -C "$S4_WORK/tier1-device" S4Tier1.app

echo "== building Tier1 app (simulator)"
configure_app "$S4_ROOT/Spike/S4/Tier1" "$S4_WORK/tier1-sim" sim -DFREECAD_SRC_DIR="$FC_SRC"
cmake --build "$S4_WORK/tier1-sim" -j3 2>&1 | tee "$OUT/tier1-sim-build.log"
APP_SIM="$S4_WORK/tier1-sim/S4Tier1.app"
test -d "$APP_SIM"
lipo -info "$APP_SIM/S4Tier1"

echo "== running Tier1 in iOS Simulator (SIMULATOR evidence)"
run_in_simulator "$APP_SIM" "com.user.freecad.s4tier1" "s4_tier1_result.txt" "$OUT/sim"

# pull the in-app captured frame too
UDID_APP_CONTAINER="$(find "$HOME/Library/Developer/CoreSimulator/Devices" -name 's4_tier1_frame.png' 2>/dev/null | head -1 || true)"
if [ -n "$UDID_APP_CONTAINER" ]; then cp "$UDID_APP_CONTAINER" "$OUT/sim/" || true; fi

if [ -f "$OUT/sim/simulator-screenshot.png" ]; then
	python3 "$S4_ROOT/Spike/S4/tools/png_stats.py" "$OUT/sim/simulator-screenshot.png" \
		> "$OUT/sim/screenshot-stats.json" || true
	cat "$OUT/sim/screenshot-stats.json" || true
fi
if [ -f "$OUT/sim/s4_tier1_frame.png" ]; then
	python3 "$S4_ROOT/Spike/S4/tools/png_stats.py" "$OUT/sim/s4_tier1_frame.png" \
		> "$OUT/sim/frame-stats.json" || true
	cat "$OUT/sim/frame-stats.json" || true
fi

echo "== Tier1 verdict inputs:"
cat "$OUT/sim/s4_tier1_result.txt" 2>/dev/null || echo "NO RESULT FILE — see app-console.log"
echo "== tier1 script done"
