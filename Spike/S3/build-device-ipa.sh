#!/bin/bash
# Spike S3 Phase A1 — DEVICE IPA packaging (added for the on-device
# proof Sean can install; the A1 harness itself is unchanged).
#
# Same pinned BeeWare asset as Scripts/build-python.sh /
# Spike/S3/build-and-run.sh. Builds the harness for device
# (iphoneos, arm64) ONLY, assembles/signs the .app exactly as
# build-and-run.sh does, then zips it as an unsigned IPA:
#   dist-s3-ipa/S3-PythonSpike-unsigned.ipa   (Payload/S3Spike.app/…)
#
# "Unsigned" = ad-hoc codesigned (codesign --sign -), no provisioning
# profile — the standard sideload shape used across this user's
# projects (the installer re-signs). This script NEVER runs the app:
# device runtime evidence is Sean's run, not CI's.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
HARNESS="Spike/S3"

PYTHON_VERSION="3.13.18"
SUPPORT_TAG="3.13-b18"
ASSET="Python-3.13-iOS-support.b18.tar.gz"
URL="https://github.com/beeware/Python-Apple-support/releases/download/${SUPPORT_TAG}/${ASSET}"
SHA256="d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"
BUNDLE_ID="org.freecad.s3spike"

WORK="${RUNNER_TEMP:-/tmp}/s3-device-ipa"
rm -rf "$WORK"; mkdir -p "$WORK" dist-s3-ipa
OUT_DIR="$PWD/dist-s3-ipa"
IPA="$OUT_DIR/S3-PythonSpike-unsigned.ipa"

echo "== Download BeeWare ${SUPPORT_TAG} (Python ${PYTHON_VERSION}) =="
curl -fL --retry 3 -o "$WORK/$ASSET" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
[ "$ACTUAL" = "$SHA256" ] || { echo "SHA256 MISMATCH: $ACTUAL"; exit 1; }
echo "sha256 verified: $ACTUAL"
tar -xzf "$WORK/$ASSET" -C "$WORK"
XCF="$WORK/Python.xcframework"
TEMPLATE="$XCF/build/iOS-dylib-Info-template.plist"
[ -f "$TEMPLATE" ] || { echo "dynload framework template missing"; exit 1; }
SLICE_DIR="$XCF/ios-arm64"
[ -d "$SLICE_DIR/Python.framework" ] || { echo "device slice missing"; exit 1; }

echo "== Build (iphoneos, arm64-apple-ios17.0) =="
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 \
  -fobjc-arc -O1 \
  -F"$SLICE_DIR" \
  -framework Python -framework Foundation -framework UIKit \
  -Wl,-rpath,@executable_path/Frameworks \
  "$HARNESS/main.m" -o "$WORK/S3Spike-iphoneos"
file "$WORK/S3Spike-iphoneos"
file "$WORK/S3Spike-iphoneos" | grep -q "arm64" \
  || { echo "device binary is not arm64"; exit 1; }

APP="$WORK/S3Spike.app"
echo "== Assemble $APP =="
rm -rf "$APP"; mkdir -p "$APP/Frameworks"
cp "$WORK/S3Spike-iphoneos" "$APP/S3Spike"
cp "$HARNESS/Info.plist" "$APP/Info.plist"
cp "$HARNESS/probe.py" "$APP/probe.py"
echo -n "APPL????" > "$APP/PkgInfo"
cp -R "$SLICE_DIR/Python.framework" "$APP/Frameworks/Python.framework"
mkdir -p "$APP/python/lib"
rsync -a "$XCF/lib/" "$APP/python/lib/"
rsync -a "$SLICE_DIR/lib-arm64/" "$APP/python/lib/"
python3 "$HARNESS/convert_dynload.py" "$APP" "$TEMPLATE" "$BUNDLE_ID"

echo "== Ad-hoc sign (inside-out) =="
for fw in "$APP"/Frameworks/*.framework; do
  codesign --force --sign - --timestamp=none "$fw"
done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=2 "$APP" || true

{
  echo "device binary:"
  file "$APP/S3Spike"
  echo "device Python.framework:"
  file "$APP/Frameworks/Python.framework/Python"
  echo "DEVICE-BUILD-OK"
} > "$OUT_DIR/device-build.txt"
cat "$OUT_DIR/device-build.txt"

echo "== Package IPA =="
rm -rf "$WORK/Payload" "$IPA"
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/S3Spike.app"
(cd "$WORK" && zip -qry "$IPA" Payload)
[ -f "$IPA" ] || { echo "IPA not produced"; exit 1; }
unzip -l "$IPA" | head -30
ls -lh "$IPA"
shasum -a 256 "$IPA"
echo "S3-DEVICE-IPA-OK $IPA"
