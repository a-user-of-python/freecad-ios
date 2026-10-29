#!/bin/bash
# S1 — Foundations (REAL stage).
#
# Builds into ios-prefix/ (workspace-local), all static iOS arm64 via
# the iOS kit's qt.toolchain.cmake + QT_HOST_PATH, deployment target
# 17.0, in order:
#   zlib 1.3.1 -> FreeType 2.13.3 -> HarfBuzz 10.4.0 -> yaml-cpp 0.8.0
#   -> Xerces-C 3.3.0 -> Eigen 3.4.0 (headers copied) -> Boost 1.88.0
#   (program_options, thread, date_time as compiled .a; regex is
#   header-only INTERFACE in 1.88's CMake build — see Boost section).
#
# Xerces-C transcoder choice: Xerces-C 3.3.0's CMake offers icu /
# macosunicodeconverter / gnuiconv / iconv / windows — there is NO
# built-in transcoder option in 3.3.0, so this stage uses
# transcoder=gnuiconv, i.e. the SYSTEM iconv in the iOS SDK. NO ICU
# is built or linked. Network accessor is OFF.
#
# Boost route: Boost's own CMake superproject build with
# BOOST_INCLUDE_LIBRARIES — NOT b2 (b2's darwin toolset grabs the
# macOS sysroot instead of iphoneos; synthesis §3/S1 trap).
#
# Boost version is 1.88.0 per the live conda-forge pinning for the
# pinned FreeCAD snapshot (libboost_devel 1.88) — the proven pairing.
#
# Each library self-verifies after install: lipo -info shows arm64
# on a produced .a + one nm symbol grep (Eigen is header-only: its
# version macros are checked instead). Output package:
# dist/iosdeps-foundations-$DEPS_HASH.tar.zst containing ios-prefix/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/foundations"
PREFIX="$ROOT/ios-prefix"
SRCDIR="$WORK/src"
DIST="$ROOT/dist"
DEPS_HASH="${DEPS_HASH:-local}"
mkdir -p "$WORK" "$SRCDIR" "$DIST"
rm -rf "$PREFIX"; mkdir -p "$PREFIX"

# shellcheck source=qt-install.inc.sh
. "$ROOT/Scripts/qt-install.inc.sh"

NCPU="$(sysctl -n hw.ncpu)"
TOOLCHAIN="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake"

# CMAKE_OSX_SYSROOT is the resolved SDK path from qt-install.inc.sh
# (modern CMake 4.x fatals when it is left as the "iphoneos" name,
# and xcrun cannot be trusted on every runner — see the include).
COMMON=(
	-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
	-DQT_HOST_PATH="$QT_DESKTOP"
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
	-DCMAKE_INSTALL_PREFIX="$PREFIX"
	-DCMAKE_PREFIX_PATH="$PREFIX;$QT_IOS"
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
	-DBUILD_SHARED_LIBS=OFF
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
)

fetch() { # fetch <tarball-url> <top-dir>
	local url="$1" top="$2"
	if [ ! -d "$SRCDIR/$top" ]; then
		echo "== fetching $url"
		curl -fsSL --retry 3 -o "$WORK/dl.tar" "$url"
		rm -rf "$SRCDIR/.extract"; mkdir -p "$SRCDIR/.extract"
		tar -xf "$WORK/dl.tar" -C "$SRCDIR/.extract"
		mv "$SRCDIR/.extract/$top" "$SRCDIR/$top"
		rm -rf "$SRCDIR/.extract" "$WORK/dl.tar"
	fi
}

verify_lib() { # verify_lib <label> <lib-file-relative-to-prefix> <symbol-regex>
	local label="$1" lib="$PREFIX/$2" sym="$3"
	echo "== verifying $label: $2"
	test -f "$lib" || { echo "ERROR: $label archive missing: $lib" >&2; exit 1; }
	lipo -info "$lib" | tee "$WORK/verify-$label.txt"
	grep -q "arm64" "$WORK/verify-$label.txt" || { echo "ERROR: $label is not arm64" >&2; exit 1; }
	nm "$lib" > "$WORK/nm-$label.txt" 2>/dev/null || true
	grep -q "$sym" "$WORK/nm-$label.txt" || { echo "ERROR: $label symbol '$sym' not found" >&2; exit 1; }
	echo "   OK (arm64, symbol $sym present)"
}

build_cmake() { # build_cmake <label> <srcdir> <extra cmake args...>
	local label="$1" src="$2"; shift 2
	echo "== configuring $label"
	cmake -S "$src" -B "$WORK/build-$label" -G Ninja "${COMMON[@]}" "$@"
	echo "== building $label"
	cmake --build "$WORK/build-$label" -j"$NCPU"
	cmake --install "$WORK/build-$label"
}

# ---------------------------------------------------------- zlib 1.3.1
fetch "https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz" "zlib-1.3.1"
echo "== configuring zlib"
cmake -S "$SRCDIR/zlib-1.3.1" -B "$WORK/build-zlib" -G Ninja "${COMMON[@]}"
echo "== building zlib (static target only)"
cmake --build "$WORK/build-zlib" -j"$NCPU" --target zlibstatic
ZLIB_A="$(find "$WORK/build-zlib" -name "*.a" | head -1)"
test -n "$ZLIB_A"
mkdir -p "$PREFIX/include" "$PREFIX/lib"
cp "$ZLIB_A" "$PREFIX/lib/libz.a"
cp "$SRCDIR/zlib-1.3.1/zlib.h" "$PREFIX/include/zlib.h"
cp "$WORK/build-zlib/zconf.h" "$PREFIX/include/zconf.h"
verify_lib "zlib" "lib/libz.a" "zlibVersion"

# ---------------------------------------------------------- FreeType 2.13.3
fetch "https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-3.tar.gz" "freetype-VER-2-13-3"
build_cmake "freetype" "$SRCDIR/freetype-VER-2-13-3" \
	-DFT_WITH_ZLIB=ON -DFT_WITH_HARFBUZZ=OFF -DFT_WITH_PNG=OFF \
	-DFT_WITH_BZIP2=OFF -DFT_WITH_BROTLI=OFF
verify_lib "freetype" "lib/libfreetype.a" "FT_Init_FreeType"

# ---------------------------------------------------------- HarfBuzz 10.4.0
fetch "https://github.com/harfbuzz/harfbuzz/releases/download/10.4.0/harfbuzz-10.4.0.tar.xz" "harfbuzz-10.4.0"
build_cmake "harfbuzz" "$SRCDIR/harfbuzz-10.4.0" \
	-DHB_HAVE_FREETYPE=ON -DHB_HAVE_CORETEXT=OFF -DHB_HAVE_ICU=OFF \
	-DHB_HAVE_GLIB=OFF -DHB_HAVE_GRAPHITE2=OFF -DHB_HAVE_GOBJECT=OFF \
	-DHB_HAVE_CAIRO=OFF -DHB_BUILD_SUBSET=OFF -DHB_BUILD_UTILS=OFF
verify_lib "harfbuzz" "lib/libharfbuzz.a" "hb_buffer_create"

# ---------------------------------------------------------- yaml-cpp 0.8.0
fetch "https://github.com/jbeder/yaml-cpp/archive/refs/tags/0.8.0.tar.gz" "yaml-cpp-0.8.0"
build_cmake "yaml-cpp" "$SRCDIR/yaml-cpp-0.8.0" \
	-DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF \
	-DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_BUILD_SHARED_LIBS=OFF
verify_lib "yaml-cpp" "lib/libyaml-cpp.a" "YAML"

# ---------------------------------------------------------- Xerces-C 3.3.0
# Transcoder: gnuiconv = system iconv (see header). NO ICU.
fetch "https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-3.3.0.tar.gz" "xerces-c-3.3.0"
# gnuiconv availability depends on the SDK iconv probe at configure
# time; if it is not offered, fall back to the plain iconv transcoder
# (also system facilities, still no ICU) and record which one won.
XERCES_TRANSCODER="gnuiconv"
if ! cmake -S "$SRCDIR/xerces-c-3.3.0" -B "$WORK/build-xerces" -G Ninja "${COMMON[@]}" \
	-Dtranscoder=gnuiconv -Dnetwork=OFF -DBUILD_TESTING=OFF -DCMAKE_MACOSX_BUNDLE=OFF >"$WORK/xerces-config-gnuiconv.log" 2>&1; then
	echo "== xerces gnuiconv transcoder unavailable; falling back to iconv"
	cat "$WORK/xerces-config-gnuiconv.log"
	rm -rf "$WORK/build-xerces"
	XERCES_TRANSCODER="iconv"
	cmake -S "$SRCDIR/xerces-c-3.3.0" -B "$WORK/build-xerces" -G Ninja "${COMMON[@]}" \
		-Dtranscoder=iconv -Dnetwork=OFF -DBUILD_TESTING=OFF -DCMAKE_MACOSX_BUNDLE=OFF
fi
echo "== building xerces (transcoder=$XERCES_TRANSCODER)"
cmake --build "$WORK/build-xerces" -j"$NCPU"
cmake --install "$WORK/build-xerces"
XERCES_A="$(find "$PREFIX/lib" -name "libxerces-c*.a" | head -1)"
test -n "$XERCES_A"
verify_lib "xerces" "${XERCES_A#"$PREFIX"/}" "xercesc"

# ---------------------------------------------------------- Eigen 3.4.0 (headers)
fetch "https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz" "eigen-3.4.0"
echo "== installing Eigen headers"
mkdir -p "$PREFIX/include/eigen3"
cp -R "$SRCDIR/eigen-3.4.0/Eigen" "$PREFIX/include/eigen3/"
cp -R "$SRCDIR/eigen-3.4.0/unsupported" "$PREFIX/include/eigen3/"
cp "$SRCDIR/eigen-3.4.0/signature_of_eigen3_matrix_library" "$PREFIX/include/eigen3/"
test -f "$PREFIX/include/eigen3/Eigen/Core"
grep -q "EIGEN_WORLD_VERSION 3" "$PREFIX/include/eigen3/Eigen/src/Core/util/Macros.h"
grep -q "EIGEN_MAJOR_VERSION 4" "$PREFIX/include/eigen3/Eigen/src/Core/util/Macros.h"
echo "   OK (Eigen 3.4 headers in include/eigen3)"

# ---------------------------------------------------------- Boost 1.88.0
# CMake superproject route ONLY (never b2). Compiled libs only:
# program_options, regex, thread, date_time (+ their CMake-resolved
# dependencies, which BOOST_INCLUDE_LIBRARIES pulls in automatically).
#
# SOURCE TRUTH (verified 2026-10-29 by direct download + tar listing):
# the archives.boost.io release tarball (boost_1_88_0.tar.gz,
# 168,473,737 B, sha256 3621533e820dcab1e8012afd583c0c73cf0f7769495
# 2b81352bf38c1488f9cb4) is the b2-layout archive: its root contains
# Jamroot / boost-build.jam / bootstrap.sh and NO CMakeLists.txt —
# CMakeLists.txt exists only under libs/<lib>/. Configuring it as a
# superproject therefore always fails with "source directory ...
# does not appear to contain CMakeLists.txt" (run 40944904578).
# The superproject CMakeLists.txt ships in the SEPARATE CMake release
# asset on GitHub: boost-1.88.0-cmake.tar.gz (132,402,054 B, sha256
# dcea50f40ba1ecfc448fdf886c0165cf3e525fef2c9e3e080b9804e8117b9694,
# top dir boost-1.88.0/, root CMakeLists.txt present, libs'
# program_options/regex/thread/date_time sources + CMakeLists all
# present — same verified tar listing). Use that asset.
fetch "https://github.com/boostorg/boost/releases/download/boost-1.88.0/boost-1.88.0-cmake.tar.gz" "boost-1.88.0"
test -f "$SRCDIR/boost-1.88.0/CMakeLists.txt" || { echo "ERROR: Boost -cmake tarball layout changed: no root CMakeLists.txt in boost-1.88.0/" >&2; exit 1; }
grep -q "project(Boost VERSION 1.88.0" "$SRCDIR/boost-1.88.0/CMakeLists.txt" || { echo "ERROR: Boost root CMakeLists.txt is not 1.88.0" >&2; exit 1; }
build_cmake "boost" "$SRCDIR/boost-1.88.0" \
	-DBOOST_INCLUDE_LIBRARIES="program_options;regex;thread;date_time" \
	-DBOOST_ENABLE_CMAKE=ON
verify_lib "boost-program_options" "lib/libboost_program_options.a" "program_options"
# Boost.Regex 1.88 is HEADER-ONLY in the CMake superproject: its own
# libs/regex/CMakeLists.txt declares `add_library(boost_regex
# INTERFACE)` (verified in the -cmake tarball), so no
# libboost_regex.a exists to verify — the compiled src/*.cpp are the
# legacy b2 route only. Verify the installed INTERFACE package
# instead: headers + CMake config package.
echo "== verifying boost-regex (header-only INTERFACE library in 1.88)"
test -f "$PREFIX/include/boost/regex.hpp" || { echo "ERROR: boost regex.hpp header missing" >&2; exit 1; }
test -f "$PREFIX/lib/cmake/boost_regex-1.88.0/boost_regex-config.cmake" || { echo "ERROR: boost_regex CMake config missing" >&2; exit 1; }
echo "   OK (boost/regex.hpp + boost_regex-1.88.0 CMake config present; no .a by design)"
verify_lib "boost-thread" "lib/libboost_thread.a" "thread"
verify_lib "boost-date_time" "lib/libboost_date_time.a" "date_time"

# ---------------------------------------------------------- package
command -v zstd >/dev/null || brew install zstd
echo "== installed foundations tree:"
find "$PREFIX" -type f | sort | sed 's/^/   /'
TARBALL="$DIST/iosdeps-foundations-$DEPS_HASH.tar.zst"
rm -f "$TARBALL"
tar -cf - -C "$ROOT" ios-prefix | zstd -19 -f -o "$TARBALL"
ls -lh "$TARBALL"
{
	echo "S1 foundations — report"
	echo "Qt (toolchain): $QT_VERSION (ios kit $QT_IOS, host $QT_DESKTOP)"
	echo "Prefix: ios-prefix/ (static, iOS arm64, deployment target 17.0)"
	echo "Libraries: zlib 1.3.1, FreeType 2.13.3, HarfBuzz 10.4.0, yaml-cpp 0.8.0,"
	echo "  Xerces-C 3.3.0 (transcoder=$XERCES_TRANSCODER / system iconv, network OFF, no ICU),"
	echo "  Eigen 3.4.0 (headers), Boost 1.88.0 (CMake -cmake asset; program_options/thread/date_time .a, regex header-only)"
	echo "Tarball: dist/iosdeps-foundations-$DEPS_HASH.tar.zst"
} | tee "$DIST/foundations-report.txt"
echo "== S1 done"
