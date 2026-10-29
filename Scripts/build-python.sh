#!/bin/bash
# S3 chain — Python for iOS (REAL stage, spike S3 Phase A1, 2026-10-29).
#
# Route: BeeWare Python-Apple-support PREBUILT XCFramework (no source
# build required; the PEP 730 upstream source build is the documented
# fallback/audit path only — see hidden research front 03 §1).
#
# PINNED ARTIFACT (recorded 2026-10-29 from the GitHub release API;
# the asset digest below is the release's own published sha256, and
# was independently re-verified by downloading the asset):
#   Support release : 3.13-b18 (published 2026-10-26)
#   Python version  : 3.13.18 (per the release notes)
#   URL             : https://github.com/beeware/Python-Apple-support/releases/download/3.13-b18/Python-3.13-iOS-support.b18.tar.gz
#   sha256          : d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d
#   Bundled libs (release notes): OpenSSL 3.5.9-1, libFFI 3.4.7-2,
#                     BZip2 1.0.8-2, mpdecimal 4.0.0-2, XZ 5.6.4-2
#   Slices          : ios-arm64 (device) + ios-arm64_x86_64-simulator
#
# Output: dist/iosdeps-python-$DEPS_HASH.tar.zst containing
#   ios-prefix/Python.xcframework          (verbatim, all slices)
#   ios-prefix/include/python3.13/         (device-slice headers, for
#                                           CMake find_package consumers)
#   ios-prefix/lib/python3.13/             (common stdlib .py tree)
#   ios-prefix/PYTHON-RELEASE.txt          (this pin, machine-readable)
set -euo pipefail

PYTHON_VERSION="3.13.18"
SUPPORT_TAG="3.13-b18"
ASSET="Python-3.13-iOS-support.b18.tar.gz"
URL="https://github.com/beeware/Python-Apple-support/releases/download/${SUPPORT_TAG}/${ASSET}"
SHA256="d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"

echo "=============================================================="
echo " STAGE S3-chain (Python): BeeWare ${SUPPORT_TAG} / Python ${PYTHON_VERSION}"
echo "=============================================================="

WORK="${RUNNER_TEMP:-/tmp}/python-ios-build"
rm -rf "$WORK"; mkdir -p "$WORK" dist
PREFIX="$WORK/ios-prefix"
mkdir -p "$PREFIX"

echo "== Download =="
curl -fL --retry 3 -o "$WORK/$ASSET" "$URL"
echo "== Verify sha256 =="
ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
echo "expected: $SHA256"
echo "actual:   $ACTUAL"
[ "$ACTUAL" = "$SHA256" ] || { echo "SHA256 MISMATCH — refusing to package"; exit 1; }

echo "== Extract =="
tar -xzf "$WORK/$ASSET" -C "$WORK"
XCF="$WORK/Python.xcframework"
[ -d "$XCF" ] || { echo "Python.xcframework missing from asset"; exit 1; }
[ -d "$XCF/ios-arm64/Python.framework" ] || { echo "device slice missing"; exit 1; }
[ -d "$XCF/ios-arm64_x86_64-simulator/Python.framework" ] || { echo "simulator slice missing"; exit 1; }

echo "== Verify slice architectures =="
file "$XCF/ios-arm64/Python.framework/Python"
file "$XCF/ios-arm64_x86_64-simulator/Python.framework/Python"
if command -v lipo >/dev/null 2>&1; then
  lipo -info "$XCF/ios-arm64/Python.framework/Python"
  lipo -info "$XCF/ios-arm64_x86_64-simulator/Python.framework/Python"
fi
# The device slice must contain arm64; grep the file(1) output so a
# wrong-architecture asset fails here, not at link time downstream.
file "$XCF/ios-arm64/Python.framework/Python" | grep -q "arm64" \
  || { echo "device slice is not arm64"; exit 1; }

echo "== Stage ios-prefix =="
cp -R "$XCF" "$PREFIX/Python.xcframework"
mkdir -p "$PREFIX/include" "$PREFIX/lib"
cp -R "$XCF/ios-arm64/include/python3.13" "$PREFIX/include/python3.13"
# Common (pure-Python) stdlib tree; per-slice lib-dynload stays inside
# the XCFramework slices, where the embedding harness picks it up.
cp -R "$XCF/lib/python3.13" "$PREFIX/lib/python3.13"
{
  echo "python_version=$PYTHON_VERSION"
  echo "beeware_support_tag=$SUPPORT_TAG"
  echo "source_url=$URL"
  echo "source_sha256=$SHA256"
  echo "openssl=3.5.9-1 libffi=3.4.7-2 bzip2=1.0.8-2 mpdecimal=4.0.0-2 xz=5.6.4-2"
} > "$PREFIX/PYTHON-RELEASE.txt"
cat "$PREFIX/PYTHON-RELEASE.txt"

echo "== Package =="
if ! command -v zstd >/dev/null 2>&1; then
  echo "zstd not on PATH; installing via Homebrew"
  brew install zstd
fi
OUT="dist/iosdeps-python-${DEPS_HASH:-local}.tar.zst"
COPYFILE_DISABLE=1 tar --zstd -cf "$OUT" -C "$WORK" ios-prefix
ls -lh "$OUT"
echo "PYTHON-DEPS-OK $OUT"
