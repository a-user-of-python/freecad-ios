#!/bin/bash
# Spike S3 Phase A1 — embedding proof.
#
# Downloads the SAME pinned BeeWare asset as Scripts/build-python.sh
# (keep the two pins in sync; build-python.sh is the canonical one),
# then:
#   1. builds the harness app for the iOS Simulator (arm64),
#   2. builds it for device (iphoneos, arm64) — compile/link/package
#      proof only, never installed,
#   3. assembles each .app by hand (no Xcode project): embeds
#      Python.framework, installs the stdlib into <app>/python/lib
#      (BeeWare install_python layout) and converts every lib-dynload
#      .so into a signed .framework + .fwork pointer,
#   4. boots a simulator, installs + launches the sim app, and
#      retrieves Documents/s3-result.txt from the app container.
#
# PASS = the retrieved report contains PYTHON-EMBED-OK and PROBE-DONE.
# Outputs land in dist-s3/ for the workflow to upload.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
HARNESS="Spike/S3"

PYTHON_VERSION="3.13.18"
SUPPORT_TAG="3.13-b18"
ASSET="Python-3.13-iOS-support.b18.tar.gz"
URL="https://github.com/beeware/Python-Apple-support/releases/download/${SUPPORT_TAG}/${ASSET}"
SHA256="d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"
BUNDLE_ID="org.freecad.s3spike"

WORK="${RUNNER_TEMP:-/tmp}/s3-spike"
rm -rf "$WORK"; mkdir -p "$WORK" dist-s3
OUT="dist-s3"

echo "== Download BeeWare ${SUPPORT_TAG} (Python ${PYTHON_VERSION}) =="
curl -fL --retry 3 -o "$WORK/$ASSET" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA256" ] || { echo "SHA256 MISMATCH: $ACTUAL"; exit 1; }
echo "sha256 verified: $ACTUAL"
tar -xzf "$WORK/$ASSET" -C "$WORK"
XCF="$WORK/Python.xcframework"
TEMPLATE="$XCF/build/iOS-dylib-Info-template.plist"
[ -f "$TEMPLATE" ] || { echo "dynload framework template missing"; exit 1; }

build_app() {
  # $1 sdk  $2 xcframework slice  $3 clang target  $4 output .app path
  local sdk="$1" slice="$2" target="$3" app="$4"
  local slice_dir="$XCF/$slice"
  echo "== Build ($sdk, $target) =="
  xcrun --sdk "$sdk" clang -target "$target" \
    -fobjc-arc -O1 \
    -F"$slice_dir" \
    -framework Python -framework Foundation -framework UIKit \
    -Wl,-rpath,@executable_path/Frameworks \
    "$HARNESS/main.m" -o "$WORK/S3Spike-$sdk"
  file "$WORK/S3Spike-$sdk"

  echo "== Assemble $app =="
  rm -rf "$app"; mkdir -p "$app/Frameworks"
  cp "$WORK/S3Spike-$sdk" "$app/S3Spike"
  cp "$HARNESS/Info.plist" "$app/Info.plist"
  cp "$HARNESS/probe.py" "$app/probe.py"
  echo -n "APPL????" > "$app/PkgInfo"
  cp -R "$slice_dir/Python.framework" "$app/Frameworks/Python.framework"
  mkdir -p "$app/python/lib"
  rsync -a "$XCF/lib/" "$app/python/lib/"
  rsync -a "$slice_dir/lib-arm64/" "$app/python/lib/"
  python3 "$HARNESS/convert_dynload.py" "$app" "$TEMPLATE" "$BUNDLE_ID"

  echo "== Ad-hoc sign (inside-out) =="
  local fw
  for fw in "$app"/Frameworks/*.framework; do
    codesign --force --sign - --timestamp=none "$fw"
  done
  codesign --force --sign - --timestamp=none "$app"
  codesign --verify --verbose=2 "$app" || true
}

SIM_APP="$WORK/S3Spike-sim.app"
DEV_APP="$WORK/S3Spike-device.app"
build_app iphonesimulator ios-arm64_x86_64-simulator \
  arm64-apple-ios17.0-simulator "$SIM_APP"
build_app iphoneos ios-arm64 arm64-apple-ios17.0 "$DEV_APP"

{
  echo "device binary:"
  file "$DEV_APP/S3Spike"
  echo "device Python.framework:"
  file "$DEV_APP/Frameworks/Python.framework/Python"
} > "$OUT/device-build.txt"
cat "$OUT/device-build.txt"
file "$DEV_APP/S3Spike" | grep -q "arm64" \
  || { echo "device binary is not arm64"; exit 1; }
echo "DEVICE-BUILD-OK" >> "$OUT/device-build.txt"

echo "== Boot simulator =="
UDID="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
devs = [d for v in data.values() for d in v if d.get("isAvailable")]
prefs = [d for d in devs if "iPad" in d["name"]] or \
        [d for d in devs if "iPhone" in d["name"]] or devs
print(prefs[0]["udid"])')"
echo "simulator UDID: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "== Install + launch (SIMULATOR) =="
xcrun simctl install "$UDID" "$SIM_APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" || true

RESULT=""
for i in $(seq 1 45); do
  CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
  if [ -n "$CONTAINER" ] && [ -f "$CONTAINER/Documents/s3-result.txt" ]; then
    if grep -qE "PROBE-DONE|PYTHON-EMBED-FAIL|PROBE-EXCEPTION" \
        "$CONTAINER/Documents/s3-result.txt"; then
      RESULT="$CONTAINER/Documents/s3-result.txt"
      break
    fi
  fi
  sleep 2
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

if [ -z "$RESULT" ]; then
  echo "FAIL: no completed s3-result.txt from the simulator app"
  CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
  [ -n "$CONTAINER" ] && find "$CONTAINER" -type f | head -50 || true
  exit 1
fi
cp "$RESULT" "$OUT/s3-result-simulator.txt"
echo "================ S3 RESULT (SIMULATOR) ================"
cat "$OUT/s3-result-simulator.txt"
echo "======================================================="
grep -q "PYTHON-EMBED-OK" "$OUT/s3-result-simulator.txt" \
  || { echo "FAIL: PYTHON-EMBED-OK marker missing"; exit 1; }
grep -q "PROBE-DONE" "$OUT/s3-result-simulator.txt" \
  || { echo "FAIL: probe did not run to completion"; exit 1; }
echo "SPIKE-S3-A1-SIMULATOR-OK"
