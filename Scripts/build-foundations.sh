#!/bin/bash
# S1 — Foundations (REAL stage).
#
# Builds into ios-prefix/ (workspace-local), all static iOS arm64 via
# the iOS kit's qt.toolchain.cmake + QT_HOST_PATH, deployment target
# 17.0, in order:
#   zlib 1.3.1 -> FreeType 2.13.3 -> HarfBuzz 10.4.0 -> yaml-cpp 0.8.0
#   -> Xerces-C 3.3.0 -> ICU 78.1 -> Eigen 3.4.0 (headers copied)
#   -> Boost 1.88.0 (program_options, thread, date_time as compiled
#   .a; regex is header-only INTERFACE in 1.88's CMake build — see
#   Boost section). ICU is the one non-CMake stage: it cross-builds
#   with its own autoconf recipe (host build + --with-cross-build),
#   driven by the same SDK / deployment target — see the ICU section.
#
# Xerces-C transcoder choice: Xerces-C 3.3.0's CMake offers icu /
# macosunicodeconverter / gnuiconv / iconv / windows — there is NO
# built-in transcoder option in 3.3.0, so this stage uses
# transcoder=gnuiconv, i.e. the SYSTEM iconv in the iOS SDK. Xerces
# itself links NO ICU (the separate ICU stage below exists for
# FreeCAD's own top-level find_package(ICU), not for Xerces).
# Network accessor is OFF.
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
# Transcoder: gnuiconv = system iconv (see header); Xerces links no ICU.
fetch "https://archive.apache.org/dist/xerces/c/3/sources/xerces-c-3.3.0.tar.gz" "xerces-c-3.3.0"
# gnuiconv availability depends on the SDK iconv probe at configure
# time; if it is not offered, fall back to the plain iconv transcoder
# (also system facilities; Xerces never links ICU either way) and
# record which one won.
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

# ---------------------------------------------------------- ICU 78.1
# WHY: the pinned FreeCAD snapshot's top-level CMakeLists.txt:98 runs
# find_package(ICU REQUIRED COMPONENTS uc i18n) BEFORE the Qt stage.
# The Qt-gate probe (goal research/qt-gate-probe.md, definitive run
# 40971926782) proved CMake's FindICU in cross mode CANNOT be
# satisfied by the iOS SDK's libicucore: seven seeding layouts were
# tried, all failed — no iOS uc/i18n libraries exist in the SDK in a
# form FindICU accepts. A real iOS ICU build is therefore required;
# it gates the probe's Phase 2 and Stage 7's configure identically.
#
# VERSION PIN (verified 2026-10-29 against the GitHub release API):
# the probe evidence saw host icu4c 78.1 (the Homebrew icu4c on the
# runners), and 78.1 is the initial ICU 78 release (2025-10-30,
# Unicode 17 / CLDR 48). Later releases exist (78.2 / 78.3
# maintenance, 79.1) but the pin of record is the probe's 78.1.
#   URL:    https://github.com/unicode-org/icu/releases/download/release-78.1/icu4c-78.1-sources.tgz
#   Size:   27,979,449 bytes (release asset metadata)
#   sha256: 6217f58ca39b23127605cfc6c7e0d3475fe4b0d63157011383d716cb41617886
#           (the release API's own published asset digest; re-verified
#           in-script on every download below)
#
# DATA CHOICE: FULL data library. The target is configured with
# --with-data-packaging=library, so the complete CLDR/Unicode data
# set is compiled into libicudata.a (tens of MB — a stub would be
# ~10 KB, and the size is asserted after install). The alternative,
# stubdata (an empty libicudata plus an external .dat file the app
# must locate and load at runtime), was rejected: an iOS app bundle
# has no reliable external-data path, and FreeCAD's consumers need
# working uc/i18n behaviour, not just link symbols. With the full
# library the prefix is self-contained: libicudata.a + libicuuc.a +
# libicui18n.a resolve every uc/i18n symbol at link time.
#
# RECIPE (standard ICU cross-build; ICU is autoconf, not CMake, so
# the Qt toolchain file does not apply — the SDK path, deployment
# target 17.0 and static-only shape mirror the CMake stages):
#   1. host build (native macOS) of the same tarball — produces the
#      build tools the target build runs (pkgdata, genrb, icupkg,
#      makeconv, ...). Static, samples/tests off.
#   2. target configure from a separate build dir:
#      --host=arm-apple-darwin --with-cross-build=<host build dir>,
#      CC/CXX = the iphoneos clang/clang++ (via xcrun, honouring the
#      DEVELOPER_DIR exported by qt-install.inc.sh), flags carry
#      -arch arm64 -isysroot $IOS_SDK_PATH -miphoneos-version-min=17.0,
#      --enable-static --disable-shared, install into $PREFIX.
# Default symbol renaming is KEPT (u_strlen -> u_strlen_78 etc.):
# consumers compile against these same headers, and renaming matches
# the host Homebrew 78.1 the probe observed.
ICU_VERSION="78.1"
ICU_URL="https://github.com/unicode-org/icu/releases/download/release-78.1/icu4c-78.1-sources.tgz"
ICU_SHA256="6217f58ca39b23127605cfc6c7e0d3475fe4b0d63157011383d716cb41617886"
echo "== ICU $ICU_VERSION: fetching $ICU_URL"
if [ ! -f "$SRCDIR/icu-78.1-source/runConfigureICU" ]; then
	curl -fsSL --retry 3 -o "$WORK/icu-sources.tgz" "$ICU_URL"
	ICU_ACTUAL="$(shasum -a 256 "$WORK/icu-sources.tgz" | awk '{print $1}')"
	echo "   sha256 expected: $ICU_SHA256"
	echo "   sha256 actual:   $ICU_ACTUAL"
	[ "$ICU_ACTUAL" = "$ICU_SHA256" ] || { echo "ERROR: ICU tarball sha256 mismatch" >&2; exit 1; }
	rm -rf "$SRCDIR/.extract-icu"; mkdir -p "$SRCDIR/.extract-icu"
	tar -xzf "$WORK/icu-sources.tgz" -C "$SRCDIR/.extract-icu"
	rm -f "$WORK/icu-sources.tgz"
	# Locate icu4c/source without assuming the tarball's top-dir name
	# (release tarballs unpack to icu/source; be liberal anyway).
	ICU_FOUND=""
	for cand in "$SRCDIR/.extract-icu/icu/source" "$SRCDIR/.extract-icu/icu4c/source" "$SRCDIR/.extract-icu/source"; do
		if [ -f "$cand/runConfigureICU" ]; then ICU_FOUND="$cand"; break; fi
	done
	if [ -z "$ICU_FOUND" ]; then
		ICU_FOUND="$(dirname "$(find "$SRCDIR/.extract-icu" -name runConfigureICU -print -quit)")"
	fi
	[ -n "$ICU_FOUND" ] && [ -f "$ICU_FOUND/configure" ] || { echo "ERROR: icu4c source dir not found in tarball" >&2; exit 1; }
	mv "$ICU_FOUND" "$SRCDIR/icu-78.1-source"
	rm -rf "$SRCDIR/.extract-icu"
fi
ICU_SRC="$SRCDIR/icu-78.1-source"
echo "   icu4c source: $ICU_SRC"

echo "== ICU host build (native macOS; provides the cross-build tools)"
ICU_HOST_BUILD="$WORK/build-icu-host"
rm -rf "$ICU_HOST_BUILD" "$WORK/icu-host-prefix"; mkdir -p "$ICU_HOST_BUILD"
(
	cd "$ICU_HOST_BUILD"
	"$ICU_SRC/configure" --prefix="$WORK/icu-host-prefix" \
		--enable-static --disable-shared \
		--disable-samples --disable-tests
) > "$WORK/icu-host-configure.log" 2>&1 || { echo "ERROR: ICU host configure failed" >&2; tail -30 "$WORK/icu-host-configure.log" >&2; exit 1; }
make -C "$ICU_HOST_BUILD" -j"$NCPU" > "$WORK/icu-host-build.log" 2>&1 || { echo "ERROR: ICU host build failed" >&2; tail -30 "$WORK/icu-host-build.log" >&2; exit 1; }
test -f "$ICU_HOST_BUILD/config/icucross.mk" || { echo "ERROR: host build lacks config/icucross.mk (needed by --with-cross-build)" >&2; exit 1; }
test -x "$ICU_HOST_BUILD/bin/pkgdata" || { echo "ERROR: host build lacks bin/pkgdata" >&2; exit 1; }
echo "   host tools OK (pkgdata, icucross.mk present)"

# SDK for the target: qt-install.inc.sh resolved IOS_SDK_PATH and
# exported DEVELOPER_DIR. ICU's autoconf configure cannot fall back
# the way CMake can — it needs a real sysroot — so recover once
# (xcode-select reset + filesystem scan, the probe's pattern) and
# fail loudly if there is genuinely no iPhoneOS SDK on this runner.
if [ -z "${IOS_SDK_PATH:-}" ] || [ ! -d "$IOS_SDK_PATH" ]; then
	echo "== ICU: iPhoneOS SDK recovery (inc returned '${IOS_SDK_PATH:-empty}')"
	if [ -d /Applications/Xcode.app ]; then
		sudo xcode-select -s /Applications/Xcode.app 2>/dev/null || true
		IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
	fi
	if [ -z "${IOS_SDK_PATH:-}" ] || [ ! -d "$IOS_SDK_PATH" ]; then
		IOS_SDK_PATH=""
		for devdir in /Applications/Xcode*.app/Contents/Developer; do
			[ -d "$devdir" ] || continue
			candidate="$(DEVELOPER_DIR="$devdir" xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
			if [ -d "$candidate" ]; then IOS_SDK_PATH="$candidate"; DEVELOPER_DIR="$devdir"; break; fi
			for sdk in "$devdir"/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk; do
				if [ -d "$sdk" ]; then IOS_SDK_PATH="$sdk"; DEVELOPER_DIR="$devdir"; break 2; fi
			done
		done
	fi
	export DEVELOPER_DIR IOS_SDK_PATH
	echo "   recovered SDK: '${IOS_SDK_PATH:-STILL EMPTY}'"
fi
[ -n "${IOS_SDK_PATH:-}" ] && [ -d "$IOS_SDK_PATH" ] || { echo "ERROR: ICU target build needs a real iPhoneOS SDK; none found on this runner" >&2; exit 1; }

echo "== ICU target build (iOS arm64, sysroot $IOS_SDK_PATH)"
ICU_CC="$(xcrun --sdk iphoneos --find clang 2>/dev/null || command -v clang)"
ICU_CXX="$(xcrun --sdk iphoneos --find clang++ 2>/dev/null || command -v clang++)"
ICU_AR="$(xcrun --sdk iphoneos --find ar 2>/dev/null || command -v ar)"
ICU_RANLIB="$(xcrun --sdk iphoneos --find ranlib 2>/dev/null || command -v ranlib)"
ICU_TARGET_FLAGS="-arch arm64 -isysroot $IOS_SDK_PATH -miphoneos-version-min=17.0"
ICU_IOS_BUILD="$WORK/build-icu-ios"
rm -rf "$ICU_IOS_BUILD"; mkdir -p "$ICU_IOS_BUILD"
(
	cd "$ICU_IOS_BUILD"
	env CC="$ICU_CC" CXX="$ICU_CXX" AR="$ICU_AR" RANLIB="$ICU_RANLIB" \
		CFLAGS="$ICU_TARGET_FLAGS -O2" \
		CXXFLAGS="$ICU_TARGET_FLAGS -O2 -std=c++17" \
		CPPFLAGS="-isysroot $IOS_SDK_PATH" \
		LDFLAGS="$ICU_TARGET_FLAGS" \
		"$ICU_SRC/configure" \
			--host=arm-apple-darwin \
			--with-cross-build="$ICU_HOST_BUILD" \
			--prefix="$PREFIX" \
			--enable-static --disable-shared \
			--with-data-packaging=library \
			--disable-samples --disable-tests --disable-extras
) > "$WORK/icu-ios-configure.log" 2>&1 || { echo "ERROR: ICU target configure failed" >&2; tail -30 "$WORK/icu-ios-configure.log" >&2; exit 1; }
# Target build/install is driven PER SUBDIRECTORY (stubdata, common,
# i18n, data, io, tools/toolutil) — never the top-level tools/.
# Reason (run 40975251721 evidence): the top-level make also compiles
# the tool EXECUTABLES for the target, and tools/pkgdata/pkgdata.cpp
# calls system(), which the iPhoneOS 26 SDK headers mark explicitly
# unavailable for iOS — a hard clang error. In a cross build those
# executables are never run (the data build executes the HOST tools
# via --with-cross-build), so building them for iOS is pure loss.
# What consumers need is libraries + data + headers: libicudata,
# libicuuc, libicui18n, libicuio and the toolutil library libicutu.
# The top-level Makefile normally creates the build tree's lib/ and
# bin/ output dirs before recursing; per-subdir builds must create
# them first (run 40977103722: common's ar failed with
# "../lib/libicuuc.a: No such file or directory").
mkdir -p "$ICU_IOS_BUILD/lib" "$ICU_IOS_BUILD/bin"
for icudir in stubdata common i18n data io tools/toolutil; do
	iculog="${icudir//\//_}"
	echo "== ICU target: make -C $icudir"
	make -C "$ICU_IOS_BUILD/$icudir" -j"$NCPU" > "$WORK/icu-ios-build-$iculog.log" 2>&1 \
		|| { echo "ERROR: ICU target build failed in $icudir" >&2; tail -30 "$WORK/icu-ios-build-$iculog.log" >&2; exit 1; }
done
: > "$WORK/icu-ios-install.log"
for icudir in stubdata common i18n data io tools/toolutil; do
	make -C "$ICU_IOS_BUILD/$icudir" install >> "$WORK/icu-ios-install.log" 2>&1 \
		|| { echo "ERROR: ICU target install failed in $icudir" >&2; tail -30 "$WORK/icu-ios-install.log" >&2; exit 1; }
done
# Best-effort: icu-config + pkg-config files live outside the library
# subdirs (normally installed by the top-level install). FindICU does
# not require them (the probe disables PkgConfig and asserts direct
# prefix resolution), but Stage 7 may consult them — copy if present.
ICU_CONFIG_BIN="$(find "$ICU_IOS_BUILD" -maxdepth 3 -name icu-config -type f 2>/dev/null | head -1)"
if [ -n "$ICU_CONFIG_BIN" ]; then
	mkdir -p "$PREFIX/bin"
	sed "s|^prefix=.*|prefix=\"$PREFIX\"|" "$ICU_CONFIG_BIN" > "$PREFIX/bin/icu-config" || cp "$ICU_CONFIG_BIN" "$PREFIX/bin/icu-config"
	chmod +x "$PREFIX/bin/icu-config"
	echo "   installed bin/icu-config (from $ICU_CONFIG_BIN)"
fi
mkdir -p "$PREFIX/lib/pkgconfig"
for pc in $(find "$ICU_IOS_BUILD" -maxdepth 3 -name 'icu-*.pc' 2>/dev/null); do
	sed "s|^prefix=.*|prefix=$PREFIX|" "$pc" > "$PREFIX/lib/pkgconfig/$(basename "$pc")" || cp "$pc" "$PREFIX/lib/pkgconfig/"
done
ls "$PREFIX/lib/pkgconfig/" | grep -i icu || echo "   (no icu .pc files generated; not required)"
# The prefix contract is STATIC ONLY, but pkgdata's library packaging
# on darwin emits a shared data library next to the archive (run
# 40982745579 artifact listing: a full 32 MB arm64
# libicudata.78.1.dylib + two symlinks alongside libicudata.a,
# despite --disable-shared). An iOS consumer resolving the data
# component could pick the .dylib and inherit an embed/sign burden
# the static design exists to avoid — remove the shared set; the
# verified carriers are the .a archives.
if ls "$PREFIX"/lib/libicudata*.dylib >/dev/null 2>&1; then
	echo "   removing shared libicudata*.dylib from the prefix (static-only contract; libicudata.a carries the full data)"
	rm -f "$PREFIX"/lib/libicudata*.dylib
fi
ls "$PREFIX/lib/" | grep -i dylib && { echo "ERROR: shared libraries remain in the static prefix" >&2; exit 1; } || echo "   prefix lib/ is static-only (no .dylib)"
# Symbol greps are prefix substrings on purpose: default ICU renaming
# exports u_strlen_78 / unum_open_78 / icudt78l_dat, all matched here.
verify_lib "icuuc" "lib/libicuuc.a" "u_strlen"
verify_lib "icui18n" "lib/libicui18n.a" "unum_open"
verify_lib "icudata" "lib/libicudata.a" "icudt"
# Full-data proof: the stub library is ~10 KB; the full data library
# for 78.1 is tens of MB. Anything under 5 MB means the data did not
# actually get compiled in, whatever configure claimed.
ICU_DATA_SIZE="$(stat -f %z "$PREFIX/lib/libicudata.a" 2>/dev/null || stat -c %s "$PREFIX/lib/libicudata.a")"
echo "   libicudata.a size: $ICU_DATA_SIZE bytes (full data library, NOT stubdata)"
[ "$ICU_DATA_SIZE" -gt 5000000 ] || { echo "ERROR: libicudata.a is stub-sized ($ICU_DATA_SIZE B); full data was not built" >&2; exit 1; }

# FindICU proof — the exact operation the probe showed failing with
# the SDK's libicucore: a CMake project that runs
# find_package(ICU REQUIRED COMPONENTS uc i18n) under the iOS
# toolchain against THIS prefix and LINKS a program calling
# u_strlen + u_errorName. PkgConfig discovery is disabled so the
# host's Homebrew icu4c 78.1 cannot masquerade as a find result, and
# the resolved library paths are asserted to live under $PREFIX —
# FINDICU-OK therefore means OUR iOS libraries satisfied FindICU.
echo "== FindICU probe (find_package(ICU uc i18n) + link, iOS toolchain)"
ICU_PROBE="$WORK/icu-probe"
rm -rf "$ICU_PROBE"; mkdir -p "$ICU_PROBE"
cat > "$ICU_PROBE/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(icu_findicu_probe CXX)
find_package(ICU REQUIRED COMPONENTS uc i18n)
add_executable(icu_probe main.cpp)
target_link_libraries(icu_probe PRIVATE ICU::uc ICU::i18n)
EOF
cat > "$ICU_PROBE/main.cpp" <<'EOF'
#include <unicode/ustring.h>
#include <unicode/utypes.h>
#include <cstdio>
#include <cstring>
int main() {
    const UChar s[] = {0x0048, 0x0069, 0x0000};
    const int32_t n = u_strlen(s);
    const char *e = u_errorName(U_ZERO_ERROR);
    std::printf("u_strlen=%d u_errorName=%s\n", (int)n, e);
    return (n == 2 && std::strcmp(e, "U_ZERO_ERROR") == 0) ? 0 : 1;
}
EOF
# ICU_INCLUDE_DIR is seeded to the prefix on purpose (run
# 40981512637 evidence): unseeded, FindICU resolved the include dir
# to the SDK sysroot's /usr/include — whose libicucore headers are
# configured WITHOUT symbol renaming, so the probe compiled
# references to _u_strlen/_u_errorName while our libraries export
# the renamed _u_strlen_78/_u_errorName_78, and the link failed on
# exactly those two symbols. Seeding the prefix headers (renaming
# ON, matching the libraries) is the feedstock-style fix; the
# assertion below proves the seed took.
cmake -S "$ICU_PROBE" -B "$WORK/build-icu-probe" -G Ninja "${COMMON[@]}" \
	-DICU_ROOT="$PREFIX" \
	-DICU_INCLUDE_DIR="$PREFIX/include" \
	-DICU_INCLUDE_DIRS="$PREFIX/include" \
	-DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=TRUE \
	> "$WORK/icu-probe-configure.log" 2>&1 || { echo "ERROR: FindICU probe configure failed" >&2; cat "$WORK/icu-probe-configure.log" >&2; exit 1; }
grep -i "Found ICU" "$WORK/icu-probe-configure.log" || true
grep -q "ICU_INCLUDE_DIR.*$PREFIX/include" "$WORK/build-icu-probe/CMakeCache.txt" || { echo "ERROR: FindICU include dir is not the iOS prefix (SDK header masquerade?)" >&2; exit 1; }
grep -E "ICU.*(LIBRARY|LIBRARIES)" "$WORK/build-icu-probe/CMakeCache.txt" || true
# The resolved uc/i18n libraries must be THIS prefix's iOS archives —
# checked against both the cache and the generated link line so the
# assertion does not depend on FindICU's internal cache-var naming.
for iculib in libicuuc libicui18n; do
	grep -q "$PREFIX/lib/$iculib" "$WORK/build-icu-probe/CMakeCache.txt" "$WORK/build-icu-probe/build.ninja" 2>/dev/null \
		|| { echo "ERROR: FindICU did not resolve $iculib from the iOS prefix (host masquerade?)" >&2; exit 1; }
done
cmake --build "$WORK/build-icu-probe" -j"$NCPU" > "$WORK/icu-probe-build.log" 2>&1 || { echo "ERROR: FindICU probe link failed" >&2; cat "$WORK/icu-probe-build.log" >&2; exit 1; }
ICU_PROBE_BIN="$(find "$WORK/build-icu-probe" -name icu_probe -type f | head -1)"
test -n "$ICU_PROBE_BIN"
file "$ICU_PROBE_BIN" | grep -q "arm64" || { echo "ERROR: FindICU probe binary is not arm64" >&2; exit 1; }
echo "FINDICU-OK (find_package(ICU uc i18n) satisfied by $PREFIX; probe links u_strlen + u_errorName; binary is arm64)"

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
	echo "  Xerces-C 3.3.0 (transcoder=$XERCES_TRANSCODER / system iconv, network OFF; Xerces links no ICU),"
	echo "  ICU 78.1 (autoconf cross-build, host tools + arm-apple-darwin target; static uc/i18n + FULL data library, not stubdata; FindICU probe: FINDICU-OK),"
	echo "  Eigen 3.4.0 (headers), Boost 1.88.0 (CMake -cmake asset; program_options/thread/date_time .a, regex header-only)"
	echo "Tarball: dist/iosdeps-foundations-$DEPS_HASH.tar.zst"
} | tee "$DIST/foundations-report.txt"
echo "== S1 done"
