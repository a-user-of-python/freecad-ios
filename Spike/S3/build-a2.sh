#!/bin/bash
# Spike S3 Phase A2 — FreeCAD console stack on the embedded interpreter.
#
# GATE first (deliberate): refuses to build until both A2 dependency
# tarballs exist in ./ios-deps-artifacts/ (downloaded by
# spike-s3-a2.yml from the deps-foundations / deps-occt runs) AND
# contain real ios-prefix/ trees (not STAGE-NOT-IMPLEMENTED shells):
#   iosdeps-foundations-<hash>.tar.zst   (S1: Boost, Xerces-C, Eigen…)
#   iosdeps-occt-8.0.1-<hash>.tar.zst    (S2: full ${OCC_LIBRARIES} set)
# plus the Python prefix from deps-python (Scripts/build-python.sh).
#
# EXECUTION (synthesis §1.4/§3, front 03 Phase A), all SIMULATOR:
#   1. Extract the three deps prefixes; verify ios-prefix/ is real.
#   2. Platform probe: the deps prefixes are DEVICE arm64 builds.
#      Try linking a simulator binary against them. If ld refuses
#      (expected), rebuild the two compiled deps FOR THE SIMULATOR:
#      OCCT via a sed-adapted copy of Scripts/build-occt.sh, and the
#      foundations compiled libs via the S1 recipes with a plain
#      iOS-simulator CMake toolchain (headers are platform-neutral
#      and are reused from the device prefix).
#   3. Qt 6.9.3 dual kit via Scripts/qt-install.inc.sh (FEBio recipe).
#   4. Download the pinned weekly FreeCAD tarball (PIN.md values,
#      sha256-verified) and configure the CONSOLE stack only:
#      BUILD_GUI=OFF, FREECAD_USE_PYSIDE/SHIBOKEN=OFF,
#      FREECAD_CHECK_PYSIDE/PIVY=OFF, BUILD_DYNAMIC_LINK_PYTHON=OFF,
#      FREECAD_USE_PCL=OFF, modules = Part, PartDesign, Sketcher,
#      Import, Mesh, Spreadsheet, Test (everything else OFF, FEM/
#      SMESH OFF), Python3 = BeeWare prefix (host interpreter for
#      build-time codegen), OCC/Boost/Xerces/Eigen = deps prefixes.
#   5. Build + install, then package PACKAGING MODEL 1 (front 03
#      §1): install tree (lib/ + Mod/ + Ext/) copied into the A2
#      harness app bundle, ad-hoc signed in-bundle, loaded by the
#      normal import system (dlopen). ESCALATION (pre-planned): if
#      the probe reports an import/dlopen failure, repackage the
#      extension modules as .framework + .fwork (the A1-proven
#      BeeWare route) and run once more before declaring anything.
#   6. Run probe_a2.py in the harness on the SIMULATOR and compare
#      its numbers against the analytic/desktop references:
#      STEP-VOLUME 6000, PARTDESIGN-VOLUME 6283.185307, round-trip
#      == PartDesign volume. Divergence = §3 kill criterion.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root
ROOT="$PWD"
HARNESS="Spike/S3"

missing=0
for pat in "iosdeps-foundations-*.tar.zst" "iosdeps-occt-*.tar.zst" \
           "iosdeps-python-*.tar.zst"; do
  if ! ls ios-deps-artifacts/$pat >/dev/null 2>&1; then
    echo "A2 PENDING DEPS: ios-deps-artifacts/$pat not present"
    missing=1
  fi
done
if [ "$missing" = 1 ]; then
  echo "A2-GATE-CLOSED (deps not landed; nothing built, nothing failed)"
  exit 0
fi
echo "A2-GATE-OPEN: all dependency tarballs present."

mkdir -p dist-s3-a2
OUT="$ROOT/dist-s3-a2"
A2W="$ROOT/build-a2"
rm -rf "$A2W"; mkdir -p "$A2W"
NCPU="$(sysctl -n hw.ncpu)"

# ---------------------------------------------------------- deps extract
DEPS="$A2W/deps"; mkdir -p "$DEPS/foundations" "$DEPS/occt" "$DEPS/python"
tar --zstd -xf ios-deps-artifacts/iosdeps-foundations-*.tar.zst -C "$DEPS/foundations"
tar --zstd -xf ios-deps-artifacts/iosdeps-occt-*.tar.zst -C "$DEPS/occt"
tar --zstd -xf ios-deps-artifacts/iosdeps-python-*.tar.zst -C "$DEPS/python"
for p in foundations occt python; do
  if [ ! -d "$DEPS/$p/ios-prefix" ]; then
    echo "A2-DEP-NOT-REAL: $p artifact has no ios-prefix/ (placeholder?)"
    find "$DEPS/$p" | head -20
    exit 1
  fi
done
FOUND_DEV="$DEPS/foundations/ios-prefix"
OCCT_DEV="$DEPS/occt/ios-prefix"
PY_PREFIX="$DEPS/python/ios-prefix"
echo "== deps prefixes (device arm64 originals) =="
ls "$FOUND_DEV" "$OCCT_DEV" "$PY_PREFIX"
test -f "$OCCT_DEV/lib/libTKernel.a" || { echo "OCCT prefix lacks libTKernel.a"; exit 1; }
test -d "$PY_PREFIX/Python.xcframework" || { echo "Python prefix lacks xcframework"; exit 1; }
echo "A2-DEPS-REAL-OK"

# ---------------------------------------------------------- SDK discovery
find_sdk() { # $1 = sdk name (iphonesimulator|iphoneos)
  local name="$1" path=""
  path="$(xcrun --sdk "$name" --show-sdk-path 2>/dev/null || true)"
  if [ ! -d "$path" ]; then
    local devdir sdk
    for devdir in /Applications/Xcode*.app/Contents/Developer; do
      [ -d "$devdir" ] || continue
      path="$(DEVELOPER_DIR="$devdir" xcrun --sdk "$name" --show-sdk-path 2>/dev/null || true)"
      if [ -d "$path" ]; then export DEVELOPER_DIR="$devdir"; break; fi
      for sdk in "$devdir/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator"*.sdk \
                 "$devdir/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS"*.sdk; do
        if [ -d "$sdk" ]; then path="$sdk"; export DEVELOPER_DIR="$devdir"; break 2; fi
      done
    done
  fi
  echo "$path"
}
SIM_SDK="$(find_sdk iphonesimulator)"
[ -d "$SIM_SDK" ] || { echo "no iPhoneSimulator SDK found"; exit 1; }
echo "== simulator SDK: $SIM_SDK (DEVELOPER_DIR=${DEVELOPER_DIR:-default})"

# ---------------------------------------------------------- platform probe
# Can a simulator binary link the DEVICE deps archives? Try with a
# translation unit that pulls real symbols from OCCT + Xerces + Boost.
cat > "$A2W/linkprobe.cpp" <<'EOF'
#include <BRepPrimAPI_MakeBox.hxx>
#include <TopoDS_Shape.hxx>
#include <xercesc/util/PlatformUtils.hpp>
#include <boost/program_options.hpp>
#include <cstdio>
int main() {
    BRepPrimAPI_MakeBox mk(30.0, 20.0, 10.0);
    mk.Build();
    std::printf("probe shape null=%d\n", mk.Shape().IsNull() ? 1 : 0);
    return 0;
}
EOF
PROBE_OK=0
if xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios17.0-simulator \
     -isysroot "$SIM_SDK" -mios-simulator-version-min=17.0 -std=gnu++17 \
     -I"$OCCT_DEV/include/opencascade" -I"$FOUND_DEV/include" \
     "$A2W/linkprobe.cpp" -o "$A2W/linkprobe" \
     -L"$OCCT_DEV/lib" -lTKPrim -lTKTopAlgo -lTKBRep -lTKGeomAlgo -lTKGeomBase \
     -lTKG3d -lTKG2d -lTKMath -lTKernel -lTKShHealing -lTKBool -lTKBO -lTKMesh \
     -L"$FOUND_DEV/lib" -lxerces-c -lboost_program_options \
     >"$OUT/platform-probe.log" 2>&1; then
  PROBE_OK=1
fi
if [ "$PROBE_OK" = 1 ]; then
  echo "A2-PLATFORM-PROBE: device deps LINK into simulator binary (using device prefixes)"
  FOUND="$FOUND_DEV"; OCCT="$OCCT_DEV"
else
  echo "A2-PLATFORM-PROBE: device deps REFUSED by simulator ld (see platform-probe.log);"
  echo "                    rebuilding OCCT + foundations compiled libs for the simulator"
  tail -5 "$OUT/platform-probe.log" || true
  FOUND="$A2W/foundations-sim/ios-prefix"
  OCCT="$A2W/occt-sim/ios-prefix"
fi

# ---------------------------------------------------------- sim deps rebuild
if [ "$PROBE_OK" = 0 ]; then
  # --- OCCT for the simulator: sed-adapted copy of the S2 script ---
  sed -e 's/arm64-apple-ios17\.0/arm64-apple-ios17.0-simulator/g' \
      -e 's/-miphoneos-version-min/-mios-simulator-version-min/g' \
      -e 's/--sdk iphoneos/--sdk iphonesimulator/g' \
      -e 's/iPhoneOS\.platform/iPhoneSimulator.platform/g' \
      -e 's/iPhoneOS\*\.sdk/iPhoneSimulator*.sdk/g' \
      Scripts/build-occt.sh > Scripts/.build-occt-sim.sh
  chmod +x Scripts/.build-occt-sim.sh
  # The script writes $ROOT/ios-prefix and $ROOT/dist; run it, then
  # move the prefix aside for A2's use.
  DEPS_HASH=sim bash Scripts/.build-occt-sim.sh >"$OUT/occt-sim-build.log" 2>&1 || {
    echo "A2-SIM-OCCT-BUILD-FAIL (tail:)"; tail -30 "$OUT/occt-sim-build.log"; exit 1; }
  mkdir -p "$A2W/occt-sim"
  mv "$ROOT/ios-prefix" "$OCCT"
  rm -f Scripts/.build-occt-sim.sh
  echo "A2-SIM-OCCT-OK: $(ls "$OCCT/lib" | wc -l | tr -d ' ') archives"

  # --- Foundations compiled libs for the simulator -----------------
  # Prefix starts as a copy of the device prefix (headers and CMake
  # configs are platform-neutral); every lib/*.a is then overwritten
  # by a simulator build using the S1 recipes + a plain toolchain.
  mkdir -p "$A2W/foundations-sim"
  cp -R "$FOUND_DEV" "$FOUND"
  SIMW="$A2W/fsim"; mkdir -p "$SIMW/src"
  cat > "$SIMW/ios-sim-toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT "$SIM_SDK" CACHE PATH "iOS simulator sysroot")
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
  SIMCOMMON=(-DCMAKE_TOOLCHAIN_FILE="$SIMW/ios-sim-toolchain.cmake"
    -DCMAKE_INSTALL_PREFIX="$FOUND" -DCMAKE_PREFIX_PATH="$FOUND"
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DBUILD_SHARED_LIBS=OFF)
  fetch_src() { # fetch_src <url> <top-dir>
    if [ ! -d "$SIMW/src/$2" ]; then
      curl -fsSL --retry 3 -o "$SIMW/dl.tar" "$1"
      rm -rf "$SIMW/.ex"; mkdir -p "$SIMW/.ex"
      tar -xf "$SIMW/dl.tar" -C "$SIMW/.ex"
      mv "$SIMW/.ex/$2" "$SIMW/src/$2"
      rm -rf "$SIMW/.ex" "$SIMW/dl.tar"
    fi
  }
  sim_cmake() { # sim_cmake <label> <srcdir> <extra...>
    local label="$1" src="$2"; shift 2
    cmake -S "$src" -B "$SIMW/build-$label" -G Ninja "${SIMCOMMON[@]}" "$@"
    cmake --build "$SIMW/build-$label" -j"$NCPU"
    cmake --install "$SIMW/build-$label"
  }
  # zlib (S1 recipe: static target only, manual install)
  fetch_src "https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz" "zlib-1.3.1"
  cmake -S "$SIMW/src/zlib-1.3.1" -B "$SIMW/build-zlib" -G Ninja "${SIMCOMMON[@]}"
  cmake --build "$SIMW/build-zlib" -j"$NCPU" --target zlibstatic
  cp "$(find "$SIMW/build-zlib" -name '*.a' | head -1)" "$FOUND/lib/libz.a"
  # FreeType / HarfBuzz / yaml-cpp (S1 recipes verbatim)
  fetch_src "https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz" "freetype-VER-2-13-3"
  sim_cmake freetype "$SIMW/src/freetype-VER-2-13-3" \
    -DFT_WITH_ZLIB=ON -DFT_WITH_HARFBUZZ=OFF -DFT_WITH_PNG=OFF \
    -DFT_WITH_BZIP2=OFF -DFT_WITH_BROTLI=OFF
  fetch_src "https://github.com/harfbuzz/harfbuzz/releases/download/10.4.0/harfbuzz-10.4.0.tar.xz" "harfbuzz-10.4.0"
  sim_cmake harfbuzz "$SIMW/src/harfbuzz-10.4.0" \
    -DHB_HAVE_FREETYPE=ON -DHB_HAVE_CORETEXT=OFF -DHB_HAVE_ICU=OFF \
    -DHB_HAVE_GLIB=OFF -DHB_HAVE_GRAPHITE2=OFF -DHB_HAVE_GOBJECT=OFF \
    -DHB_HAVE_CAIRO=OFF -DHB_BUILD_SUBSET=OFF -DHB_BUILD_UTILS=OFF
  fetch_src "https://github.com/jbeder/yaml-cpp/archive/refs/tags/0.8.0.tar.gz" "yaml-cpp-0.8.0"
  sim_cmake yaml-cpp "$SIMW/src/yaml-cpp-0.8.0" \
    -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF \
    -DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_BUILD_SHARED_LIBS=OFF
  # Xerces-C (S1 transcoder fallback logic verbatim)
  fetch_src "https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-3.3.0.tar.gz" "xerces-c-3.3.0"
  if ! cmake -S "$SIMW/src/xerces-c-3.3.0" -B "$SIMW/build-xerces" -G Ninja \
       "${SIMCOMMON[@]}" -Dtranscoder=gnuiconv -Dnetwork=OFF \
       -DBUILD_TESTING=OFF -DCMAKE_MACOSX_BUNDLE=OFF >"$OUT/xerces-sim-config.log" 2>&1; then
    echo "== xerces gnuiconv unavailable on simulator; falling back to iconv"
    rm -rf "$SIMW/build-xerces"
    cmake -S "$SIMW/src/xerces-c-3.3.0" -B "$SIMW/build-xerces" -G Ninja \
      "${SIMCOMMON[@]}" -Dtranscoder=iconv -Dnetwork=OFF \
      -DBUILD_TESTING=OFF -DCMAKE_MACOSX_BUNDLE=OFF >>"$OUT/xerces-sim-config.log" 2>&1
  fi
  cmake --build "$SIMW/build-xerces" -j"$NCPU"
  cmake --install "$SIMW/build-xerces"
  # Boost (S1 CMake-superproject recipe, re-based 2026-10-29 on
  # S1's fixed route: the boost-1.88.0-cmake.tar.gz GitHub asset —
  # the archives.boost.io tarball has no root CMakeLists.txt, which
  # killed S1 run 40944904578; regex is a header-only INTERFACE lib
  # in 1.88's CMake build, so no libboost_regex.a is expected)
  fetch_src "https://github.com/boostorg/boost/releases/download/boost-1.88.0/boost-1.88.0-cmake.tar.gz" "boost-1.88.0"
  sim_cmake boost "$SIMW/src/boost-1.88.0" \
    -DBOOST_INCLUDE_LIBRARIES="program_options;regex;thread;date_time" \
    -DBOOST_ENABLE_CMAKE=ON
  echo "A2-SIM-FOUNDATIONS-OK"
  ls -lh "$FOUND/lib"
fi
echo "== A2 prefixes in use: FOUND=$FOUND OCCT=$OCCT PY=$PY_PREFIX"

# ---------------------------------------------------------- Qt dual kit
echo "== installing Qt dual kit (qt-install.inc.sh) =="
ROOT_QT="$ROOT"; WORK="$A2W/qtstage"; mkdir -p "$WORK"
# shellcheck disable=SC1091
. "$ROOT/Scripts/qt-install.inc.sh"
ROOT="$ROOT_QT"
echo "== Qt $QT_VERSION (ios: $QT_IOS, host: $QT_DESKTOP)"

# ---------------------------------------------------------- FreeCAD source
FC_URL="https://github.com/FreeCAD/FreeCAD/releases/download/weekly-2026.09.16/freecad_source_weekly-2026.09.16.tar.gz"
FC_SHA256="1fba830dbb58c67c88222b375d336e721f03e728cdb0392b4080f6ef02fea0c4"
echo "== downloading pinned FreeCAD weekly 2026.09.16 =="
curl -fL --retry 3 -o "$A2W/freecad.tar.gz" "$FC_URL"
FC_ACTUAL="$(shasum -a 256 "$A2W/freecad.tar.gz" | awk '{print $1}')"
[ "$FC_ACTUAL" = "$FC_SHA256" ] || { echo "FREECAD SHA256 MISMATCH: $FC_ACTUAL"; exit 1; }
echo "freecad tarball sha256 verified"
FC_SRC="$A2W/freecad-src"; mkdir -p "$FC_SRC"
tar -xzf "$A2W/freecad.tar.gz" -C "$FC_SRC"
test -f "$FC_SRC/CMakeLists.txt" || { echo "freecad source layout unexpected"; ls "$FC_SRC" | head; exit 1; }

# ---------------------------------------------------------- host python
HOST_PY=""
for cand in python3.13 python3.12 python3.11 python3; do
  p="$(command -v "$cand" || true)"
  [ -n "$p" ] || continue
  if "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
    HOST_PY="$p"; break
  fi
done
if [ -z "$HOST_PY" ]; then
  echo "== no host python >=3.10; installing python@3.13 via Homebrew"
  brew install python@3.13
  HOST_PY="$(brew --prefix python@3.13)/bin/python3.13"
fi
echo "== host python (build-time codegen only): $HOST_PY ($("$HOST_PY" --version))"

# ---------------------------------------------------------- configure
PY_XCF="$PY_PREFIX/Python.xcframework"
PY_SLICE="$PY_XCF/ios-arm64_x86_64-simulator"
test -d "$PY_SLICE/Python.framework" || { echo "python simulator slice missing"; exit 1; }
FC_BUILD="$A2W/freecad-build"
FC_INSTALL="$A2W/fc-install"
echo "== configuring FreeCAD console stack (simulator arm64) =="
set +e
cmake -S "$FC_SRC" -B "$FC_BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" \
  -DQT_HOST_PATH="$QT_DESKTOP" \
  -DCMAKE_OSX_SYSROOT="$SIM_SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_INSTALL_PREFIX="$FC_INSTALL" \
  -DCMAKE_PREFIX_PATH="$FOUND;$OCCT;$QT_IOS" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -DFREECAD_QT_VERSION=6 \
  -DBUILD_GUI=OFF \
  -DENABLE_DEVELOPER_TESTS=OFF \
  -DFREECAD_USE_PYSIDE=OFF -DFREECAD_USE_SHIBOKEN=OFF \
  -DFREECAD_CHECK_PYSIDE=OFF -DFREECAD_CHECK_PIVY=OFF \
  -DBUILD_DYNAMIC_LINK_PYTHON=OFF \
  -DFREECAD_USE_PCL=OFF \
  -DBUILD_PART=ON -DBUILD_PART_DESIGN=ON -DBUILD_SKETCHER=ON \
  -DBUILD_IMPORT=ON -DBUILD_MESH=ON -DBUILD_SPREADSHEET=ON -DBUILD_TEST=ON \
  -DBUILD_FEM=OFF -DBUILD_MESH_PART=OFF -DBUILD_FLAT_MESH=OFF \
  -DBUILD_ADDONMGR=OFF -DBUILD_BIM=OFF -DBUILD_DRAFT=OFF -DBUILD_HELP=OFF \
  -DBUILD_INSPECTION=OFF -DBUILD_MATERIAL=OFF -DBUILD_OPENSCAD=OFF \
  -DBUILD_CAM=OFF -DBUILD_ASSEMBLY=OFF -DBUILD_PLOT=OFF -DBUILD_POINTS=OFF \
  -DBUILD_REVERSEENGINEERING=OFF -DBUILD_ROBOT=OFF -DBUILD_SHOW=OFF \
  -DBUILD_START=OFF -DBUILD_TECHDRAW=OFF -DBUILD_TUX=OFF -DBUILD_WEB=OFF \
  -DBUILD_SURFACE=OFF -DBUILD_MEASURE=OFF \
  -DPython3_EXECUTABLE="$HOST_PY" \
  -DPython3_ROOT_DIR="$PY_PREFIX" \
  -DPython3_INCLUDE_DIR="$PY_PREFIX/include/python3.13" \
  -DPython3_LIBRARY="$PY_SLICE/Python.framework/Python" \
  -DOCC_INCLUDE_DIR="$OCCT/include/opencascade" \
  -DOCC_LIBRARY="$OCCT/lib/libTKernel.a" \
  -DBoost_ROOT="$FOUND" -DBoost_NO_SYSTEM_PATHS=ON \
  -DXercesC_ROOT="$FOUND" \
  >"$OUT/configure.log" 2>&1
CFG_RC=$?
set -e
if [ "$CFG_RC" != 0 ]; then
  echo "A2-CONFIGURE-FAIL (tail of configure.log:)"; tail -60 "$OUT/configure.log"; exit 1
fi
echo "A2-CONFIGURE-OK"
grep -E "OpenCASCADE|Boost|Xerces|Eigen|Python3|Qt6" "$OUT/configure.log" | head -30 || true

# ---------------------------------------------------------- build + install
echo "== building FreeCAD console stack (-j$NCPU) =="
cmake --build "$FC_BUILD" -j"$NCPU" >"$OUT/build.log" 2>&1 || {
  echo "A2-BUILD-FAIL (tail of build.log:)"; tail -60 "$OUT/build.log"; exit 1; }
cmake --install "$FC_BUILD" >>"$OUT/build.log" 2>&1
echo "A2-BUILD-OK"
find "$FC_INSTALL" -maxdepth 2 | sort | head -40
du -sh "$FC_INSTALL"

# ---------------------------------------------------------- harness build
echo "== building A2 harness (simulator arm64) =="
FCINC=""
if [ -f "$FC_INSTALL/include/App/Application.h" ]; then
  FCINC="$FC_INSTALL/include"
elif [ -f "$FC_SRC/src/App/Application.h" ]; then
  FCINC="$FC_SRC/src"
fi
[ -n "$FCINC" ] || { echo "cannot locate FreeCAD headers"; exit 1; }
# Generated headers (FCConfig.h, Build/Version.h) live in the build tree.
GENINC1="$FC_BUILD"; GENINC2="$FC_BUILD/src"
QTINC="$QT_IOS/include"
xcrun --sdk iphonesimulator clang++ -target arm64-apple-ios17.0-simulator \
  -isysroot "$SIM_SDK" -mios-simulator-version-min=17.0 \
  -std=gnu++17 -fobjc-arc -O1 \
  -I"$FCINC" -I"$GENINC1" -I"$GENINC2" \
  -I"$PY_PREFIX/include/python3.13" \
  -I"$QTINC" -I"$QTINC/QtCore" -I"$QTINC/QtXml" -I"$QTINC/QtNetwork" \
  -I"$QTINC/QtConcurrent" -I"$OCCT/include/opencascade" -I"$FOUND/include" \
  -I"$FOUND/include/eigen3" \
  -F"$PY_SLICE" -F"$QT_IOS/lib" \
  -framework Python -framework Foundation -framework UIKit \
  -L"$FC_INSTALL/lib" -lFreeCADApp -lFreeCADBase \
  -Wl,-rpath,@executable_path/Frameworks \
  -Wl,-rpath,@executable_path/lib \
  "$HARNESS/main_a2.mm" -o "$A2W/S3A2-bin" \
  >"$OUT/harness-build.log" 2>&1 || {
    echo "A2-HARNESS-BUILD-FAIL (tail:)"; tail -50 "$OUT/harness-build.log"; exit 1; }
file "$A2W/S3A2-bin"
echo "A2-HARNESS-BUILD-OK"

# ---------------------------------------------------------- app assembly
BUNDLE_ID="org.freecad.s3a2spike"
TEMPLATE="$PY_XCF/build/iOS-dylib-Info-template.plist"
test -f "$TEMPLATE" || { echo "dynload framework template missing in xcframework"; exit 1; }

assemble_app() { # $1 = framework-convert FreeCAD modules (0/1)
  local convert_fc="$1"
  local app="$A2W/S3A2.app"
  rm -rf "$app"; mkdir -p "$app/Frameworks"
  cp "$A2W/S3A2-bin" "$app/S3A2"
  cp "$HARNESS/InfoA2.plist" "$app/Info.plist"
  cp "$HARNESS/probe_a2.py" "$app/probe_a2.py"
  cp "$HARNESS/probe_a2_prelude.py" "$app/probe_a2_prelude.py"
  echo -n "APPL????" > "$app/PkgInfo"
  # Python: A1 layout (framework + in-bundle stdlib + dynload conv.)
  cp -R "$PY_SLICE/Python.framework" "$app/Frameworks/Python.framework"
  mkdir -p "$app/python/lib"
  rsync -a "$PY_XCF/lib/" "$app/python/lib/"
  rsync -a "$PY_SLICE/lib-arm64/" "$app/python/lib/" 2>/dev/null || \
    rsync -a "$PY_SLICE/lib/" "$app/python/lib/"
  python3 "$HARNESS/convert_dynload.py" "$app" "$TEMPLATE" "org.freecad.s3spike"
  # FreeCAD install tree
  cp -R "$FC_INSTALL/lib" "$app/lib"
  cp -R "$FC_INSTALL/Mod" "$app/Mod"
  [ -d "$FC_INSTALL/Ext" ] && cp -R "$FC_INSTALL/Ext" "$app/Ext" || true
  [ -d "$FC_INSTALL/share" ] && cp -R "$FC_INSTALL/share" "$app/share" || true

  # Install-name fixups: every bundled Mach-O must reference bundled
  # libs via @rpath, never build-tree paths.
  local bundled=""
  bundled="$(find "$app/lib" "$app/Mod" -type f \( -name '*.so' -o -name '*.dylib' \) \
             -exec basename {} \; | sort -u)"
  fix_macho() { # $1 = file
    local f="$1" base dep name
    base="$(basename "$f")"
    if [[ "$base" == *.so || "$base" == *.dylib ]]; then
      install_name_tool -id "@rpath/$base" "$f" 2>/dev/null || true
    fi
    otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r dep; do
      name="$(basename "$dep")"
      if echo "$bundled" | grep -qx "$name"; then
        [ "$dep" = "@rpath/$name" ] || \
          install_name_tool -change "$dep" "@rpath/$name" "$f" 2>/dev/null || true
      elif [[ "$dep" == *"Python.framework"* ]]; then
        [ "$dep" = "@rpath/Python.framework/Python" ] || \
          install_name_tool -change "$dep" "@rpath/Python.framework/Python" "$f" 2>/dev/null || true
      fi
    done
    install_name_tool -add_rpath "@loader_path" "$f" 2>/dev/null || true
    install_name_tool -add_rpath "@executable_path/Frameworks" "$f" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$f" 2>/dev/null || true
    install_name_tool -add_rpath "@loader_path/../../Frameworks" "$f" 2>/dev/null || true
  }
  local f
  while IFS= read -r f; do fix_macho "$f"; done < <(
    find "$app/lib" "$app/Mod" -type f \( -name '*.so' -o -name '*.dylib' \))
  fix_macho "$app/S3A2"

  if [ "$convert_fc" = 1 ]; then
    # ESCALATION packaging: FreeCAD extension modules become
    # .framework + .fwork (BeeWare route, A1-proven mechanism).
    python3 - "$app" "$TEMPLATE" <<'PYEOF'
import os, plistlib, shutil, sys
app, template = sys.argv[1], sys.argv[2]
with open(template, "rb") as fh:
    tpl = plistlib.load(fh)
converted = []
for root, _dirs, files in os.walk(app):
    if "Frameworks" in root:
        continue
    for name in files:
        if not name.endswith(".so"):
            continue
        full = os.path.join(root, name)
        mod = name.split(".")[0]
        fw_rel = os.path.join("Frameworks", mod + ".framework")
        fw_dir = os.path.join(app, fw_rel)
        if os.path.isdir(fw_dir):
            continue
        os.makedirs(fw_dir, exist_ok=True)
        plist = dict(tpl)
        plist["CFBundleExecutable"] = mod
        plist["CFBundleIdentifier"] = ("org.freecad.s3a2spike." + mod).replace("_", "-")
        plist.pop("CFBundleName", None)
        with open(os.path.join(fw_dir, "Info.plist"), "wb") as fh:
            plistlib.dump(plist, fh)
        shutil.move(full, os.path.join(fw_dir, mod))
        with open(full[: -len(".so")] + ".fwork", "w", encoding="utf-8") as fh:
            fh.write(os.path.join(fw_rel, mod) + "\n")
        converted.append(mod)
print("framework-converted FreeCAD modules:", len(converted), converted[:20])
PYEOF
  fi

  echo "== ad-hoc sign (inside-out) =="
  local fw so
  for fw in "$app"/Frameworks/*.framework; do
    codesign --force --sign - --timestamp=none "$fw"
  done
  while IFS= read -r so; do
    codesign --force --sign - --timestamp=none "$so"
  done < <(find "$app/lib" "$app/Mod" -type f \( -name '*.so' -o -name '*.dylib' \))
  codesign --force --sign - --timestamp=none "$app"
  echo "$app"
}

# ---------------------------------------------------------- simulator run
run_on_simulator() { # $1 = label; echoes result dir into SIM_CONTAINER
  local app="$A2W/S3A2.app"
  local udid
  udid="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
devs = [d for v in data.values() for d in v if d.get("isAvailable")]
prefs = [d for d in devs if "iPad" in d["name"]] or \
        [d for d in devs if "iPhone" in d["name"]] or devs
print(prefs[0]["udid"])')"
  echo "== simulator UDID: $udid =="
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch "$udid" "$BUNDLE_ID" || true
  local i container=""
  for i in $(seq 1 150); do
    container="$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [ -n "$container" ] && [ -f "$container/Documents/s3-a2-result.txt" ]; then
      if grep -qE "A2-PROBE-DONE|A2-HARNESS-FAIL|A2-HARNESS-DONE|FREECAD-IMPORT-FAIL" \
          "$container/Documents/s3-a2-result.txt"; then
        break
      fi
    fi
    sleep 4
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  SIM_CONTAINER="$container"
}

check_numbers() { # $1 = result file; returns 0 if all numbers match
  python3 - "$1" <<'PYEOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
def num(pat):
    m = re.search(pat, text)
    return float(m.group(1)) if m else None
step = num(r"STEP-VOLUME ([0-9.]+)")
pad = num(r"PARTDESIGN-OK VOLUME ([0-9.]+)")
rt = num(r"STEP-ROUNDTRIP-VOLUME ([0-9.]+)")
print("numbers: STEP=%s PAD=%s ROUNDTRIP=%s" % (step, pad, rt))
ok = True
if step is None or abs(step - 6000.0) > 0.01: ok = False
if pad is None or abs(pad - 6283.185307) > 0.01: ok = False
if rt is None or pad is None or abs(rt - pad) > 0.01: ok = False
print("A2-NUMBERS-MATCH" if ok else "A2-NUMBERS-DIVERGE")
sys.exit(0 if ok else 1)
PYEOF
}

echo "== packaging model 1 (in-bundle dlopen) =="
assemble_app 0 >/dev/null
run_on_simulator model1
RES="$OUT/s3-a2-result-model1.txt"
PRE="$OUT/s3-a2-prelude-model1.txt"
[ -n "${SIM_CONTAINER:-}" ] && [ -f "$SIM_CONTAINER/Documents/s3-a2-result.txt" ] \
  && cp "$SIM_CONTAINER/Documents/s3-a2-result.txt" "$RES" || true
[ -n "${SIM_CONTAINER:-}" ] && [ -f "$SIM_CONTAINER/Documents/s3-a2-prelude.txt" ] \
  && cp "$SIM_CONTAINER/Documents/s3-a2-prelude.txt" "$PRE" || true
MODEL_USED="model1-dlopen"
if [ ! -f "$RES" ]; then
  echo "A2-RUN-FAIL: no result file from model-1 run"
  exit 1
fi
echo "================ S3 A2 RESULT (SIMULATOR, model 1) ================"
cat "$RES"
[ -f "$PRE" ] && { echo "--- prelude ---"; cat "$PRE"; }
if grep -qE "FREECAD-IMPORT-FAIL|PRELUDE FreeCAD import FAIL" "$RES" "$PRE" 2>/dev/null \
   || ! grep -q "A2-PROBE-DONE" "$RES"; then
  echo "== model 1 did not reach probe completion; ESCALATING to"
  echo "   framework packaging (.framework + .fwork, A1-proven route) =="
  assemble_app 1 >/dev/null
  run_on_simulator framework
  RES="$OUT/s3-a2-result-framework.txt"
  PRE="$OUT/s3-a2-prelude-framework.txt"
  [ -n "${SIM_CONTAINER:-}" ] && [ -f "$SIM_CONTAINER/Documents/s3-a2-result.txt" ] \
    && cp "$SIM_CONTAINER/Documents/s3-a2-result.txt" "$RES" || true
  [ -n "${SIM_CONTAINER:-}" ] && [ -f "$SIM_CONTAINER/Documents/s3-a2-prelude.txt" ] \
    && cp "$SIM_CONTAINER/Documents/s3-a2-prelude.txt" "$PRE" || true
  MODEL_USED="framework-fwork"
  echo "================ S3 A2 RESULT (SIMULATOR, framework) ================"
  [ -f "$RES" ] && cat "$RES" || echo "(no result file)"
  [ -f "$PRE" ] && { echo "--- prelude ---"; cat "$PRE"; }
fi
cp "$RES" "$OUT/s3-a2-result.txt"
[ -f "$PRE" ] && cp "$PRE" "$OUT/s3-a2-prelude.txt" || true
echo "A2-PACKAGING-MODEL-USED: $MODEL_USED"
grep -q "A2-PROBE-DONE" "$RES" || { echo "A2-PROBE-INCOMPLETE"; exit 1; }
if check_numbers "$RES"; then
  echo "SPIKE-S3-A2-SIMULATOR-OK"
else
  echo "SPIKE-S3-A2-DIVERGE (kill criterion: numerical/test divergence)"
  exit 1
fi
