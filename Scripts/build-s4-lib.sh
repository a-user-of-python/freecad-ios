#!/bin/bash
# Spike S4 — shared build helpers (sourced by build-s4-tier0.sh /
# build-s4-tier1.sh). Everything here runs on the macos-26 CI runner.
# Conventions follow the FEBio Studio iOS script: aqtinstall Qt 6.9.3
# dual kit with 6.8.3 fallback, host kit discovered from Qt6Config.cmake
# rather than assumed, ninja for app builds.
set -euo pipefail

S4_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S4_WORK="$S4_ROOT/build/s4"
S4_PREFIX="$S4_WORK/prefix"
S4_SRC="$S4_WORK/src"
mkdir -p "$S4_WORK" "$S4_PREFIX" "$S4_SRC"

QT_VERSION_USED=""

install_qt() {
	if [ -n "$QT_VERSION_USED" ]; then return 0; fi
	echo "== installing Qt (aqtinstall)"
	python3 -m pip install --quiet --break-system-packages aqtinstall
	local QT_ROOT="$S4_WORK/Qt"
	for v in 6.9.3 6.8.3; do
		echo "-- trying Qt $v"
		if python3 -m aqt install-qt mac desktop "$v" clang_64 -O "$QT_ROOT" --modules qtshadertools 2>/dev/null \
		   && python3 -m aqt install-qt mac ios "$v" ios -O "$QT_ROOT" --modules qtshadertools 2>/dev/null; then
			QT_VERSION_USED="$v"; break
		fi
		echo "-- Qt $v install failed, trying next candidate"
	done
	[ -n "$QT_VERSION_USED" ] || { echo "ERROR: no Qt kit installed" >&2; exit 1; }
	QT_IOS="$QT_ROOT/$QT_VERSION_USED/ios"
	QT_DESKTOP=""
	for cfg in "$QT_ROOT/$QT_VERSION_USED"/*/lib/cmake/Qt6/Qt6Config.cmake; do
		case "$cfg" in
			"$QT_IOS"/*) ;;
			*) QT_DESKTOP="$(dirname "$(dirname "$(dirname "$(dirname "$cfg")")")")" ;;
		esac
	done
	echo "== Qt $QT_VERSION_USED ready (host: $QT_DESKTOP, ios: $QT_IOS)"
	test -n "$QT_DESKTOP"
	test -f "$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake"
	command -v ninja >/dev/null || brew install ninja
	export QT_IOS QT_DESKTOP QT_VERSION_USED
}

fetch_gl4es() {
	if [ ! -d "$S4_SRC/gl4es" ]; then
		echo "== fetching gl4es v1.1.6 (ptitSeb/gl4es release tag, pinned)"
		git clone --depth 1 --branch v1.1.6 https://github.com/ptitSeb/gl4es "$S4_SRC/gl4es"
	fi
	if [ ! -f "$S4_SRC/ios-cmake/ios.toolchain.cmake" ]; then
		echo "== fetching ios-cmake (leetal/ios-cmake)"
		git clone --depth 1 https://github.com/leetal/ios-cmake "$S4_SRC/ios-cmake"
	fi
	git -C "$S4_SRC/gl4es" rev-parse HEAD | sed 's/^/gl4es commit: /' || true
	# S4 PATCH 0001 (enumerated, applied to the gl4es checkout only):
	# src/gl/attributes.h's AliasDecl uses __attribute__((alias)) under
	# __GNUC__ with NO __APPLE__ exclusion — clang/Darwin hard-errors
	# "aliases are not supported on darwin" in directstate.c. The
	# neighbouring AliasExport macro DOES exclude __APPLE__ (falls back
	# to a plain declaration). Mirror that for AliasDecl. Verified
	# present in both v1.1.6 (c9895df3) and master HEAD c1d7d014.
	# The two affected symbols get real forwarding definitions from
	# gl4es_applefix.c below.
	local AH="$S4_SRC/gl4es/src/gl/attributes.h"
	if grep -q "defined(__GNUC__) && !defined(__APPLE__)" "$AH"; then
		echo "gl4es patch 0001: already applied"
	else
		python3 - "$AH" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r"#ifdef __GNUC__(?=\s*\n\s*#define AliasDecl)")
s2, n = pat.subn("#if defined(__GNUC__) && !defined(__APPLE__)", s, count=1)
assert n == 1, "AliasDecl guard anchor not found"
open(p, "w").write(s2)
print("gl4es patch 0001: applied (AliasDecl __APPLE__ guard)")
PY
	fi
}

# build_gl4es_applefix <device|sim> — forwarding definitions for the
# two symbols patch 0001 turns into plain declarations:
# gl4es_glEnableClientStatei / gl4es_glDisableClientStatei forward to
# their *Indexed implementations (exactly what the ELF alias did).
build_gl4es_applefix() {
	local arch="$1" sdk tgt
	if [ "$arch" = device ]; then sdk=iphoneos; tgt="arm64-apple-ios17.0"; else sdk=iphonesimulator; tgt="x86_64-apple-ios17.0-simulator"; fi
	local out="$S4_PREFIX/$arch/lib"
	if [ -f "$out/libGL4ESAppleFix.a" ]; then return 0; fi
	cat > "$S4_WORK/gl4es_applefix.c" <<'EOF'
#include <GL/gl.h>
extern void gl4es_glEnableClientStateIndexed(GLenum array, GLuint index);
extern void gl4es_glDisableClientStateIndexed(GLenum array, GLuint index);
void gl4es_glEnableClientStatei(GLenum array, GLuint index) { gl4es_glEnableClientStateIndexed(array, index); }
void gl4es_glDisableClientStatei(GLenum array, GLuint index) { gl4es_glDisableClientStateIndexed(array, index); }
#undef glEnableClientStatei
#undef glDisableClientStatei
void glEnableClientStatei(GLenum array, GLuint index) { gl4es_glEnableClientStateIndexed(array, index); }
void glDisableClientStatei(GLenum array, GLuint index) { gl4es_glDisableClientStateIndexed(array, index); }
EOF
	mkdir -p "$out"
	xcrun -sdk "$sdk" clang -target "$tgt" -O2 \
		-I"$S4_PREFIX/src/gl4es/include" \
		-c "$S4_WORK/gl4es_applefix.c" -o "$S4_WORK/gl4es_applefix-$arch.o"
	xcrun -sdk "$sdk" ar rcs "$out/libGL4ESAppleFix.a" "$S4_WORK/gl4es_applefix-$arch.o"
	echo "gl4es applefix ($arch) -> $out/libGL4ESAppleFix.a"
}

# build_gl4es <device|sim> — COMPILE.md iOS recipe:
#   cmake -G Xcode -DCMAKE_TOOLCHAIN_FILE=ios.toolchain.cmake
#         -DNOX11=ON -DNOEGL=ON -DSTATICLIB=ON -DPLATFORM=OS, target GL
# Current ios-cmake names the device platform OS64 (OS is its legacy
# alias) and the Apple-Silicon simulator SIMULATORARM64; DEFAULT_ES=2
# selects the GLES2 backend (COMPILE.md "Custom build" note).
build_gl4es() {
	local arch="$1" plat sdk
	if [ "$arch" = device ]; then plat=OS64; sdk=iphoneos; else plat=SIMULATOR; sdk=iphonesimulator; fi
	local out="$S4_PREFIX/$arch/lib"
	if [ -f "$out/libGL.a" ]; then echo "== gl4es ($arch) already built"; return 0; fi
	echo "== building gl4es ($arch, PLATFORM=$plat, NOX11/NOEGL/STATICLIB, DEFAULT_ES=2)"
	# NOTE: recipe says -G Xcode; we use Ninja (same toolchain + flags)
	# because the runner's Xcode-generator support broke when sibling
	# Xcode bundles were removed (run 40917792862 Tier 0 failure #1).
	rm -rf "$S4_WORK/gl4es-$arch"
	cmake -S "$S4_SRC/gl4es" -B "$S4_WORK/gl4es-$arch" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$S4_SRC/ios-cmake/ios.toolchain.cmake" \
		-DPLATFORM="$plat" -DDEPLOYMENT_TARGET=17.0 \
		-DNOX11=ON -DNOEGL=ON -DSTATICLIB=ON -DDEFAULT_ES=2 \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build "$S4_WORK/gl4es-$arch" --target GL
	local lib
	# gl4es writes the archive into its SOURCE tree (src/gl4es/lib/),
	# not the build dir — search both (build dir first).
	lib="$(find "$S4_WORK/gl4es-$arch" "$S4_SRC/gl4es/lib" -name 'libGL.a' 2>/dev/null | head -1)"
	[ -n "$lib" ] || { echo "ERROR: libGL.a not produced for $arch" >&2; find "$S4_WORK/gl4es-$arch" -name '*.a' >&2; exit 1; }
	mkdir -p "$out"
	cp "$lib" "$out/libGL.a"
	lipo -info "$out/libGL.a"
	# headers: the app/coin/glu compiles use the gl4es source include dir
	mkdir -p "$S4_PREFIX/src"
	ln -sfn "$S4_SRC/gl4es" "$S4_PREFIX/src/gl4es"
	echo "gl4es $arch -> $out/libGL.a (sdk $sdk)"
}

# build_glu <device|sim> — companion GLU for Coin: Mesa GLU 9.0.3
# (the SGI reference GLU; gl4es README: "Standard GLU does work").
# Built by direct compilation of its libutil/libtess/libnurbs sources
# against gl4es headers — no autotools/meson cross fight.
build_glu() {
	local arch="$1" sdk tgt
	if [ "$arch" = device ]; then sdk=iphoneos; tgt="arm64-apple-ios17.0"; else sdk=iphonesimulator; tgt="x86_64-apple-ios17.0-simulator"; fi
	local out="$S4_PREFIX/$arch/lib"
	if [ -f "$out/libGLU.a" ]; then echo "== GLU ($arch) already built"; return 0; fi
	if [ ! -d "$S4_SRC/glu-9.0.3" ]; then
		echo "== fetching Mesa GLU 9.0.3"
		curl -sfL -o "$S4_WORK/glu.tar.xz" "https://archive.mesa3d.org/glu/glu-9.0.3.tar.xz" \
			|| curl -sfL -o "$S4_WORK/glu.tar.xz" "https://archive.mesa3d.org/glu/glu-9.0.2.tar.xz"
		tar -xf "$S4_WORK/glu.tar.xz" -C "$S4_SRC"
		ls -d "$S4_SRC"/glu-* | head -1
	fi
	local GLU_SRC
	GLU_SRC="$(ls -d "$S4_SRC"/glu-* | head -1)"
	echo "== compiling GLU ($arch) from $GLU_SRC"
	local objdir="$S4_WORK/glu-obj-$arch"
	rm -rf "$objdir"; mkdir -p "$objdir"
	local incs=(-I"$GLU_SRC/include" -I"$S4_PREFIX/src/gl4es/include")
	local d
	for d in $(find "$GLU_SRC/src" -type d); do incs+=(-I"$d"); done
	local n=0
	while IFS= read -r f; do
		local o="$objdir/$(echo "$f" | tr '/' '_').o"
		# Mesa GLU's libnurbs headers call assert/free without including
		# <cassert>/<cstdlib> (desktop builds get them transitively);
		# force-include the C headers so every TU sees them.
		# LIBRARYBUILD: Mesa's own build define — without it mystdio.h
		# leaves _glu_dprintf undeclared and libnurbs fails to compile.
		# Compile each file in its own language: .c as C (mipmap.c uses
		# C-only void* conversions that are hard errors in C++).
		if [ "${f##*.}" = "c" ]; then
			xcrun -sdk "$sdk" clang -target "$tgt" -std=gnu11 -O2 -DNDEBUG \
				-DLIBRARYBUILD \
				-include assert.h -include stdlib.h -include string.h -include limits.h \
				"${incs[@]}" -c "$f" -o "$o"
		else
			xcrun -sdk "$sdk" clang++ -target "$tgt" -std=c++14 -O2 -DNDEBUG \
				-DLIBRARYBUILD \
				-include assert.h -include stdlib.h -include string.h -include limits.h \
				"${incs[@]}" -c "$f" -o "$o"
		fi
		n=$((n+1))
	done < <(find "$GLU_SRC/src" -name '*.cc' -o -name '*.c' | grep -v -i 'mesa' || true)
	echo "   GLU objects: $n"
	mkdir -p "$out"
	xcrun -sdk "$sdk" ar rcs "$out/libGLU.a" "$objdir"/*.o
	# glu.h where Coin expects it (GL/glu.h next to gl4es's GL/gl.h):
	mkdir -p "$S4_PREFIX/src/glu-include/GL"
	cp "$GLU_SRC/include/GL/glu.h" "$S4_PREFIX/src/glu-include/GL/glu.h"
	lipo -info "$out/libGLU.a"
}

# Fetch unmodified Coin 4.0.10 SOURCE tarball from the coin3d GitHub
# org. Asset name verified against the release's asset list
# (coin-4.0.10-src.tar.gz, 11855404 B — NOT the first .tar.gz on the
# release, which is a macOS binary). No API call: the unauthenticated
# API rate limit killed run 40933578661's Tier 1 job. Integrity: the
# upstream-published .sha256 sidecar value, pinned here.
fetch_coin() {
	if [ -d "$S4_SRC/coin-4.0.10" ]; then return 0; fi
	echo "== fetching Coin 4.0.10 source (coin3d/coin release asset coin-4.0.10-src.tar.gz)"
	curl -sfL -o "$S4_WORK/coin.tar.gz" \
		"https://github.com/coin3d/coin/releases/download/v4.0.10/coin-4.0.10-src.tar.gz"
	echo "13fe68831292e7e725e7db1c6909d2b4fe5802080474c229fcac14ddf6445188  $S4_WORK/coin.tar.gz" | shasum -a 256 -c -
	tar -xzf "$S4_WORK/coin.tar.gz" -C "$S4_SRC"
	ls -d "$S4_SRC"/*oin* 2>/dev/null || true
	# normalise the extracted dir name to coin-4.0.10
	local d
	d="$(find "$S4_SRC" -maxdepth 1 -type d -iname '*coin*' | head -1)"
	[ -n "$d" ] || { echo "ERROR: coin source dir not found after extract" >&2; exit 1; }
	[ "$d" = "$S4_SRC/coin-4.0.10" ] || mv "$d" "$S4_SRC/coin-4.0.10"
	grep -m1 -rn "4.0.10" "$S4_SRC/coin-4.0.10/CMakeLists.txt" | head -1 || true
}

# build_coin <device|sim> — unmodified Coin against gl4es + GLU.
build_coin() {
	local arch="$1" plat
	if [ "$arch" = device ]; then plat=OS64; else plat=SIMULATOR; fi
	local out="$S4_PREFIX/$arch"
	if [ -f "$out/lib/libCoin.a" ]; then echo "== Coin ($arch) already built"; return 0; fi
	echo "== building Coin 4.0.10 ($arch) against gl4es"
	# Header shim for the Coin build ONLY (Coin + gl4es sources stay
	# untouched): gl4es's GL/gl.h force-enables its MGL namespace
	# mangling on Apple (glFoo -> gl4es_glFoo via #defines in
	# gl_mangle.h). Direct calls survive that (static linking), but
	# Coin resolves most GL entry points at RUNTIME by stringifying
	# the token — with mangling, the token stringifies to the mangled
	# name, which dlsym cannot find in a statically linked executable
	# (gl4es builds with hidden visibility). Result: every runtime-
	# resolved pointer NULL, Coin draws nothing. Fix: give Coin a
	# copy of gl4es's gl.h/glext.h with ONLY the mangling block
	# neutralised (GL_GLEXT_PROTOTYPES kept). Coin then asks dlsym
	# for plain names, which resolve to gl4es's plain-name AliasExport
	# forwarders (verified at runtime: dlsym("glGenBuffers") != NULL,
	# dlsym("gl4es_glGenBuffers") == NULL).
	local shim="$S4_WORK/coin-gl-include"
	mkdir -p "$shim/GL"
	cp "$S4_PREFIX/src/gl4es/include/GL/gl.h" "$shim/GL/gl.h"
	cp "$S4_PREFIX/src/gl4es/include/GL/glext.h" "$shim/GL/glext.h"
	python3 - "$shim/GL/gl.h" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
s2 = re.sub(r"#if defined\(__EMSCRIPTEN__\) \|\| defined\(__APPLE__\)\n"
            r"#define USE_MGL_NAMESPACE\s+1\n"
            r"#define GL_GLEXT_PROTOTYPES\s+1\n"
            r"#define MANGLE\(x\)\s+gl4es_gl##x\n"
            r"#endif",
            "#define GL_GLEXT_PROTOTYPES  1", s)
s2 = re.sub(r"#if defined\(USE_MGL_NAMESPACE\)\n#include \"gl_mangle\.h\"\n#endif\n", "", s2)
assert s2 != s and '#include "gl_mangle.h"' not in s2 and "#define USE_MGL_NAMESPACE" not in s2, "demangle failed"
open(p, "w").write(s2)
print("coin gl.h de-mangled")
PYEOF
	rm -rf "$S4_WORK/coin-$arch"
	set +e
	cmake -S "$S4_SRC/coin-4.0.10" -B "$S4_WORK/coin-$arch" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$S4_SRC/ios-cmake/ios.toolchain.cmake" \
		-DPLATFORM="$plat" -DDEPLOYMENT_TARGET=17.0 \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$out" \
		-DCOIN_BUILD_DOCUMENTATION=OFF -DCOIN_BUILD_TESTS=OFF \
		-DCOIN_BUILD_EXAMPLES=OFF -DCOIN_BUILD_SHARED_LIBS=OFF \
		-DCOIN_USE_QT=OFF \
		-DHAVE_GL_GL_H=ON -DHAVE_GL_GLU_H=ON -DHAVE_GL_GLEXT_H=ON \
		-DHAVE_DLD_LIB= -DHAVE_DYLD_RUNTIME_BINDING= \
		-DOPENGL_INCLUDE_DIR="$shim" \
		-DOPENGL_gl_LIBRARY="$out/lib/libGL.a" \
		-DOPENGL_glu_LIBRARY="$out/lib/libGLU.a" \
		-DGLU_INCLUDE_DIR="$S4_PREFIX/src/glu-include" \
		-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
		> "$S4_WORK/coin-$arch-configure.log" 2>&1
	local rc=$?
	set -e
	if [ $rc -ne 0 ]; then
		echo "ERROR: Coin configure failed ($arch); log tail:" >&2
		tail -40 "$S4_WORK/coin-$arch-configure.log" >&2
		cp "$S4_WORK/coin-$arch-configure.log" "$S4_ROOT/dist-s4/" 2>/dev/null || true
		exit 1
	fi
	# Build-configuration adjustment (Coin SOURCE stays untouched):
	# Coin's CMake sets COIN_MACOS_10/COIN_MACOS_10_3 for ANY Apple OS,
	# which turns on macOS-only code (ApplicationServices offscreen-CG
	# path, CGL, CFBundle framework lookup) that does not exist on iOS.
	# Undefine them in the GENERATED build-tree config.h only.
	local cfg
	cfg="$(find "$S4_WORK/coin-$arch" -name config.h | head -1)"
	echo "adjusting generated config.h for iOS: $cfg"
	sed -i '' -E 's|^#define COIN_MACOS_10(_3)?( .*)?$|/* iOS build-config: COIN_MACOS_10 undef (was: &) */|' "$cfg"
	grep -n "COIN_MACOS_10" "$cfg" | head -4 || true
	cmake --build "$S4_WORK/coin-$arch" -j3
	cmake --install "$S4_WORK/coin-$arch"
	find "$out" -name '*Coin*' | head
	lipo -info "$out/lib/libCoin.a"
}

# configure_app <srcdir> <builddir> <device|sim> [extra cmake -D args...]
# Qt's iOS toolchain selects device vs simulator via QT_UIKIT_SDK —
# passing CMAKE_OSX_SYSROOT alone left the kit's device-built plugin
# init objects in a simulator link (run 40938941484 Tier 0:
# "building for iOS-simulator, but linking in object file built for
# iOS"). QT_UIKIT_SDK is the toolchain's own switch.
configure_app() {
	local src="$1" bld="$2" arch="$3"; shift 3
	local uikit=iphoneos
	[ "$arch" = sim ] && uikit=iphonesimulator
	# Evidence dump: how does THIS Qt version's toolchain want the
	# device/simulator choice expressed? (fix-6 run: QT_UIKIT_SDK alone
	# left the sysroot on iphoneos; fix-5 run: CMAKE_OSX_SYSROOT alone
	# set the sysroot but kept device plugin-init objects. Pass both.)
	echo "== Qt toolchain SDK-selection machinery:"
	grep -n "UIKIT\|iphonesimulator\|CMAKE_OSX_SYSROOT" "$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" | head -25 || true
	if [ "$arch" = sim ]; then
		echo "== Qt plugin-init object evidence (fix-9 probe):"
		find "$QT_IOS/plugins" -maxdepth 3 -type d -name "objects*" | head -10 || true
		_f=$(find "$QT_IOS/plugins" -name "QGifPlugin_init.cpp.o" | head -1)
		echo "init object: $_f"; file "$_f" 2>/dev/null || true; lipo -info "$_f" 2>/dev/null || true
		_c=$(find "$QT_IOS/plugins" -name "QGifPlugin_init.cpp" | head -1)
		echo "init source present: $_c"
		grep -rn "objects-Release" "$QT_IOS/lib/cmake/Qt6Widgets/"*.cmake 2>/dev/null | head -5 || true
		grep -rln "_init" "$QT_IOS/lib/cmake/" 2>/dev/null | head -5 || true
		echo "== slice platforms (fix-11 probe): platform 2=iOS device, 7=iOS simulator"
		for _a in "$_f" \
			"$QT_IOS/plugins/platforms/objects-Release/QIOSIntegrationPlugin_init/QIOSIntegrationPlugin_init.cpp.o" \
			"$QT_IOS/lib/QtWidgets.framework/QtWidgets" \
			"$QT_IOS/lib/QtCore.framework/QtCore" \
			"$QT_IOS/plugins/platforms/libqios.a"; do
			echo "-- $_a"
			lipo -detailed_info "$_a" 2>/dev/null | grep -E "architecture|platform|sdk" | head -12 || file "$_a"
			vtool -show-build "$_a" 2>/dev/null | grep -E "architecture|platform" | head -8 || true
		done
	fi
	rm -rf "$bld"
	cmake -S "$src" -B "$bld" -G Ninja \
		-DCMAKE_TOOLCHAIN_FILE="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake" \
		-DQT_HOST_PATH="$QT_DESKTOP" \
		-DQT_UIKIT_SDK="$uikit" \
		-DCMAKE_OSX_SYSROOT="$uikit" \
		-DCMAKE_OSX_ARCHITECTURES="$([ "$arch" = sim ] && echo x86_64 || echo arm64)" \
		-DCMAKE_PREFIX_PATH="$QT_IOS" -DQt6_DIR="$QT_IOS/lib/cmake/Qt6" \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
		-DCMAKE_BUILD_TYPE=Release \
		-DS4_PREFIX="$S4_PREFIX" "$@"
}

# run_in_simulator <app> <bundle-id> <result-file-name> <outdir>
# Boots the first available simulator (iPad preferred), installs the
# app, screenshots mid-run, launches with console capture, pulls the
# app's result file from its sandbox. Evidence lands in <outdir>.
run_in_simulator() {
	local app="$1" bid="$2" resfile="$3" outdir="$4"
	mkdir -p "$outdir"
	echo "== selecting simulator"
	local udid
	udid="$(python3 - <<'PY'
import json, subprocess
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
cands = []
for runtime, devs in data["devices"].items():
    for d in devs:
        if d.get("isAvailable"):
            cands.append((0 if "iPad" in d["name"] else 1, d["udid"], d["name"]))
cands.sort()
print(cands[0][1] if cands else "")
import sys
if cands: print("SIM:", cands[0][2], file=sys.stderr)
PY
)"
	[ -n "$udid" ] || { echo "ERROR: no available simulator" >&2; xcrun simctl list devices available >&2; exit 1; }
	echo "simulator UDID: $udid"
	xcrun simctl boot "$udid" 2>/dev/null || true
	xcrun simctl bootstatus "$udid" -b
	xcrun simctl install "$udid" "$app"
	local container
	container="$(xcrun simctl get_app_container "$udid" "$bid" data 2>/dev/null || true)"
	echo "app container: $container"
	echo "== launching $bid (console captured; polling for result file)"
	# NOTE: macOS has no GNU `timeout` — the fix-14 run died here with
	# exit 127 and the app never launched. Launch in the background and
	# poll the app container for the result file instead.
	set +e
	xcrun simctl launch --console-pty "$udid" "$bid" > "$outdir/app-console.log" 2>&1 &
	local launchpid=$!
	set -e
	( for i in 4 8 12 16 20; do sleep 4; xcrun simctl io "$udid" screenshot "$outdir/simulator-screenshot-$i.png" 2>/dev/null || true; done ) &
	local shotpid=$!
	local found=""
	for i in $(seq 1 40); do
		if [ -n "$container" ] && [ -f "$container/Documents/$resfile" ]; then found=1; break; fi
		kill -0 $launchpid 2>/dev/null || break
		sleep 2
	done
	[ -n "$found" ] && sleep 2
	wait $shotpid 2>/dev/null || true
	ls -t "$outdir"/simulator-screenshot-*.png 2>/dev/null | head -1 | xargs -I{} cp {} "$outdir/simulator-screenshot.png" 2>/dev/null || true
	ls -lh "$outdir/simulator-screenshot.png" 2>/dev/null || echo "WARNING: no screenshot"
	xcrun simctl terminate "$udid" "$bid" 2>/dev/null || true
	kill $launchpid 2>/dev/null || true
	if [ -n "$container" ] && [ -f "$container/Documents/$resfile" ]; then
		cp "$container/Documents/$resfile" "$outdir/"
		echo "--- $resfile:"; cat "$outdir/$resfile"
	else
		echo "ERROR: result file $resfile not found in app sandbox — the app did not complete its run" >&2
		find "$container" -type f 2>/dev/null | head -20 || true
		echo "--- app-console.log:"; cat "$outdir/app-console.log" || true
		# Collect any crash report the simulator wrote for this app.
		local simlogs="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Logs"
		find "$simlogs" -name "*.ips" -newermt "-30 minutes" 2>/dev/null | head -5 | while read -r ips; do
			echo "--- crash report: $ips"; head -60 "$ips"
			cp "$ips" "$outdir/" 2>/dev/null || true
		done
		return 1
	fi
}
