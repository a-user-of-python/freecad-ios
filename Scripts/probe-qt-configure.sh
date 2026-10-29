#!/bin/bash
# FRONT 4 — the early Qt 6.9.3 gate probe (synthesis §1.3's deciding
# experiment, pulled forward). CONFIGURE-ONLY: this script never starts
# a FreeCAD build (Stage 7 stays gated on S3+S4).
#
# Question: does the pinned snapshot (weekly-2026.09.16, commit
# a4ce44d33b7e42e16cb8156058a1894237042ab4) CONFIGURE against the
# Qt 6.9.3 iOS kit — and if it fails, is the failure Qt-API-class
# (gate problem) or dependency/config-class (engineering)?
#
# Shape:
#   1. Qt 6.9.3 dual-kit via aqtinstall, FEBio recipe verbatim
#      (Scripts/qt-install.inc.sh: qtshadertools, dynamic kit
#      discovery, 6.8.3 fallback) + FreeCAD's extra modules from
#      synthesis §1.3 (qtsvg, qttools — SetupQt.cmake requires the
#      Svg/UiTools/LinguistTools components).
#   2. Pinned FreeCAD tarball (PIN.md URL + sha256, verified).
#   3. Deps: whatever REAL dep artifacts exist (workflow input
#      downloads in ios-deps-artifacts/, else bounded API poll via
#      Scripts/probe-deps-download.py). Merged into one ios-prefix.
#      Markers decide REAL vs shell — a ~300 B shell tarball never
#      counts.
#   4. Battery (Spike/QtGate): SetupQt.cmake's exact component list +
#      compile of the snapshot's newest-branch Qt APIs. (FreeCAD's
#      vendored QuarterWidget is S4's evidence — NOT duplicated here.)
#   5. Real configure, attempt ladder (each attempt fully logged):
#        A1 pristine synthesis set, deps as landed
#        A2 + [CONFIG] seeds: Python3 (BeeWare prefix), ICU (SDK
#           libicucore), OCC include dir — feedstock-style
#        A3 + [CONFIG] bypasses to reach the Qt stage: BUILD_FEM=OFF,
#           BUILD_MESH_PART=OFF (SMESH's VTK/MED wall is pre-Qt),
#           OpenGL/GLU seeds (iOS has no GLU; S4 owns the real one)
#      Probe-local dep fill: fmt 12.1.0 built into the prefix if no
#      fmt config landed (top-level find_package(fmt REQUIRED) runs
#      before everything; no staged workflow builds fmt yet).
#   6. Classification (Scripts/classify-qt-gate.py) -> dist-qtgate/
#      qt-gate-report.md + verdict.txt. Exit 0 always after step 1:
#      the verdict lives in the artifact (jobs+artifacts = truth).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/qtgate"
DIST="$ROOT/dist-qtgate"
SRCFC="$WORK/freecad-src"
PREFIX="$WORK/ios-prefix"
ARTDIR="$ROOT/ios-deps-artifacts"
POLL_MINUTES="${POLL_MINUTES:-45}"
mkdir -p "$WORK" "$DIST" "$PREFIX" "$ARTDIR"
cd "$ROOT"

echo "=============================================================="
echo " FRONT 4 — Qt 6.9.3 gate probe (configure-only)"
echo "=============================================================="

# ------------------------------------------------------------ 1. Qt
# qt-install.inc.sh expects ROOT + WORK and sets QT_VERSION/QT_IOS/
# QT_DESKTOP/IOS_SDK_PATH. It exits non-zero if no kit installs —
# that is a genuine GATE-BLOCKED and the workflow should show it.
. "$ROOT/Scripts/qt-install.inc.sh"

echo "== Qt $QT_VERSION: adding FreeCAD's extra modules (qtsvg, qttools)"
python3 -m aqt install-qt mac desktop "$QT_VERSION" clang_64 -O "$QT_ROOT" \
	--modules qtsvg qttools 2>&1 | tail -3 || \
	echo "WARN: desktop qtsvg/qttools add-on failed (logged; battery will classify)"
python3 -m aqt install-qt mac ios "$QT_VERSION" ios -O "$QT_ROOT" \
	--modules qtsvg qttools 2>&1 | tail -3 || \
	echo "WARN: ios qtsvg/qttools add-on failed (logged; battery will classify)"
# Re-discover the desktop kit (an add-on install must not move it, but
# FEBio's lesson is to never assume the layout).
for cfg in "$QT_ROOT/$QT_VERSION"/*/lib/cmake/Qt6/Qt6Config.cmake; do
	case "$cfg" in
		"$QT_IOS"/*) ;;
		*) QT_DESKTOP="$(dirname "$(dirname "$(dirname "$(dirname "$cfg")")")")" ;;
	esac
done
{
	echo "qt_version=$QT_VERSION"
	echo "qt_ios=$QT_IOS"
	echo "qt_desktop=$QT_DESKTOP"
	echo "ios_sdk=$IOS_SDK_PATH"
} | tee "$DIST/qt-version.txt"
command -v zstd >/dev/null 2>&1 || brew install zstd
command -v swig >/dev/null 2>&1 || brew install swig || true

TOOLCHAIN="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake"
COMMON=(
	-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
	-DQT_HOST_PATH="$QT_DESKTOP"
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
)

# ------------------------------------------------- 2. FreeCAD source
FC_URL="$(grep -o 'https://[^`]*freecad_source[^`]*\.tar\.gz' "$ROOT/PIN.md" | head -1)"
FC_SHA="$(grep 'Tarball sha256' "$ROOT/PIN.md" | grep -o '[0-9a-f]\{64\}' | head -1)"
echo "== pinned tarball: $FC_URL"
echo "   sha256 (PIN.md): $FC_SHA"
if [ ! -f "$SRCFC/CMakeLists.txt" ]; then
	curl -fsSL --retry 3 -o "$WORK/fc.tar.gz" "$FC_URL"
	ACTUAL="$(shasum -a 256 "$WORK/fc.tar.gz" | awk '{print $1}')"
	echo "   sha256 (actual): $ACTUAL"
	[ "$ACTUAL" = "$FC_SHA" ] || { echo "ERROR: tarball sha256 mismatch" >&2; exit 1; }
	mkdir -p "$SRCFC"
	tar -xzf "$WORK/fc.tar.gz" -C "$SRCFC" --strip-components=1
	rm -f "$WORK/fc.tar.gz"
fi
test -f "$SRCFC/CMakeLists.txt"
grep -m1 "a4ce44d" "$ROOT/PIN.md" >/dev/null && echo "== source extracted (PIN commit a4ce44d33b7e42e16cb8156058a1894237042ab4)"

# ------------------------------------------------------------ 3. deps
echo "== deps: collecting REAL artifacts (poll up to ${POLL_MINUTES} min)"
GH_TOKEN="${GH_TOKEN:-}" POLL_MINUTES="$POLL_MINUTES" \
	python3 "$ROOT/Scripts/probe-deps-download.py" \
		--outdir "$ARTDIR" --poll-minutes "$POLL_MINUTES" \
		2>&1 | tee "$DIST/deps-poll.log" || true
for f in "$ARTDIR"/*.tar.zst; do
	[ -f "$f" ] || continue
	echo "== unpacking $(basename "$f")"
	rm -rf "$WORK/merge"; mkdir -p "$WORK/merge"
	tar --zstd -xf "$f" -C "$WORK/merge" 2>/dev/null || tar -xf "$f" -C "$WORK/merge" || true
	if [ -d "$WORK/merge/ios-prefix" ]; then
		cp -R "$WORK/merge/ios-prefix/." "$PREFIX/" 2>/dev/null || true
	elif [ -d "$WORK/merge/dist" ]; then
		find "$WORK/merge" -name '*.tar.zst' -exec tar --zstd -xf {} -C "$WORK/merge" \; 2>/dev/null || true
		[ -d "$WORK/merge/ios-prefix" ] && cp -R "$WORK/merge/ios-prefix/." "$PREFIX/" || true
	fi
done
rm -rf "$WORK/merge"
# Inventory: marker files decide REAL vs MISSING (shell-proof).
{
	if [ -d "$PREFIX/Python.xcframework/ios-arm64" ]; then echo "python: REAL (Python.xcframework device slice present)";
	else echo "python: MISSING"; fi
	if [ -f "$PREFIX/lib/libboost_program_options.a" ] && [ -d "$PREFIX/include/eigen3/Eigen" ]; then
		echo "foundations: REAL (libboost_program_options.a + Eigen headers present)";
	else echo "foundations: MISSING"; fi
	TKC="$(ls "$PREFIX"/lib/libTK*.a 2>/dev/null | wc -l | tr -d ' ')"
	if [ -f "$PREFIX/lib/libTKHLR.a" ]; then echo "occt: REAL (libTKHLR.a present; $TKC libTK*.a total)";
	else echo "occt: MISSING ($TKC libTK*.a present)"; fi
	echo "prefix tree (top):"; find "$PREFIX" -maxdepth 2 | sort | head -40
} | tee "$DIST/deps-inventory.txt"

# --------------------------------------- probe-local fills + shims
# fmt: no staged workflow builds it yet; the pinned top-level
# CMakeLists does find_package(fmt REQUIRED) before anything else.
if ! find "$PREFIX" -name 'fmt-config.cmake' -o -name 'fmtConfig.cmake' 2>/dev/null | grep -q .; then
	echo "== probe-local fill: building fmt 12.1.0 into the prefix ([DEP] remediation)"
	FMTD="$WORK/fmt-12.1.0"
	if [ ! -d "$FMTD" ]; then
		curl -fsSL --retry 3 -o "$WORK/fmt.tar.gz" \
			"https://github.com/fmtlib/fmt/releases/download/12.1.0/fmt-12.1.0.zip" || \
		curl -fsSL --retry 3 -o "$WORK/fmt.tar.gz" \
			"https://github.com/fmtlib/fmt/archive/refs/tags/12.1.0.tar.gz"
		mkdir -p "$WORK/fmtsrc"; tar -xf "$WORK/fmt.tar.gz" -C "$WORK/fmtsrc" --strip-components=1 || \
			{ unzip -q "$WORK/fmt.tar.gz" -d "$WORK/fmtsrc-x"; mv "$WORK/fmtsrc-x"/fmt-12.1.0 "$FMTD"; }
		[ -d "$FMTD" ] || mv "$WORK/fmtsrc" "$FMTD"
	fi
	cmake -S "$FMTD" -B "$WORK/build-fmt" -G Ninja "${COMMON[@]}" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DFMT_TEST=OFF -DFMT_DOC=OFF \
		-DBUILD_SHARED_LIBS=OFF > "$DIST/fmt-build.log" 2>&1 \
		&& cmake --build "$WORK/build-fmt" -j"$(sysctl -n hw.ncpu)" >> "$DIST/fmt-build.log" 2>&1 \
		&& cmake --install "$WORK/build-fmt" >> "$DIST/fmt-build.log" 2>&1 \
		&& echo "   fmt installed" || echo "   fmt build FAILED (see fmt-build.log; configure will classify)"
fi
# OpenCASCADE config shim: real OCCT installs ship OpenCASCADEConfig.
# cmake; our S2 staging ships headers+libs only. Generate the config
# from the archives actually present — a [CONFIG] shim, labelled.
if [ -f "$PREFIX/lib/libTKHLR.a" ] && \
   ! find "$PREFIX" -iname 'OpenCASCADEConfig.cmake' 2>/dev/null | grep -q .; then
	echo "== probe shim: generating OpenCASCADEConfig.cmake from staged libTK*.a ([CONFIG])"
	OCFG="$PREFIX/lib/cmake/OpenCASCADE"; mkdir -p "$OCFG"
	TKLIBS="$(for a in "$PREFIX"/lib/libTK*.a; do basename "$a" .a | sed 's/^lib//'; done | sort | tr '\n' ';')"
	{
		echo "set(OpenCASCADE_FOUND TRUE)"
		echo "set(OpenCASCADE_VERSION \"8.0.1\")"
		echo "set(OpenCASCADE_INCLUDE_DIR \"$PREFIX/include/opencascade\")"
		echo "set(OpenCASCADE_LIBRARY_DIR \"$PREFIX/lib\")"
		echo "set(OpenCASCADE_LIBRARIES \"$TKLIBS\")"
	} > "$OCFG/OpenCASCADEConfig.cmake"
	cat "$OCFG/OpenCASCADEConfig.cmake"
fi
# GL/GLU stub archives for the A3 seed (configure-only; iOS has no
# GLU — the real companion GLU is S4 scope). Labelled [CONFIG].
mkdir -p "$WORK/glstub"
printf 'int qtgate_gl_stub;\n' > "$WORK/glstub/empty.c"
xcrun clang -target arm64-apple-ios17.0 -isysroot "$IOS_SDK_PATH" \
	-c "$WORK/glstub/empty.c" -o "$WORK/glstub/empty.o" 2>/dev/null || \
	clang -c "$WORK/glstub/empty.c" -o "$WORK/glstub/empty.o"
ar rcs "$WORK/glstub/libGL.a" "$WORK/glstub/empty.o"
ar rcs "$WORK/glstub/libGLU.a" "$WORK/glstub/empty.o"

# ---------------------------------------------------------- 4. battery
echo "== battery: Spike/QtGate against the iOS kit"
cmake -S "$ROOT/Spike/QtGate" -B "$WORK/battery" -G Ninja "${COMMON[@]}" \
	-DCMAKE_PREFIX_PATH="$PREFIX;$QT_IOS" \
	> "$DIST/battery-configure.log" 2>&1
BCFG=$?
cmake --build "$WORK/battery" -j"$(sysctl -n hw.ncpu)" \
	> "$DIST/battery-build.log" 2>&1
BBLD=$?
if [ "$BCFG" -eq 0 ] && [ "$BBLD" -eq 0 ]; then
	echo "BATTERY-RESULT: PASS" | tee "$DIST/battery-result.txt"
else
	echo "BATTERY-RESULT: FAIL (configure=$BCFG build=$BBLD)" | tee "$DIST/battery-result.txt"
fi
tail -5 "$DIST/battery-configure.log" || true

# ------------------------------------------------- 5. real configure
SYNTH=(
	-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
	-DQT_HOST_PATH="$QT_DESKTOP"
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	-DCMAKE_PREFIX_PATH="$PREFIX;$QT_IOS"
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
	-DFREECAD_QT_VERSION=6
	-DFREECAD_USE_PYSIDE=OFF
	-DFREECAD_USE_SHIBOKEN=OFF
	-DFREECAD_CHECK_PYSIDE=OFF
	-DFREECAD_CHECK_PIVY=OFF
	-DFREECAD_USE_PCL=OFF
	-DBUILD_DYNAMIC_LINK_PYTHON=OFF
	-DFREECAD_USE_PCH=OFF
	-DENABLE_DEVELOPER_TESTS=OFF
	-DBUILD_GUI=ON
	-DFREECAD_USE_EXTERNAL_FMT=OFF
	-DOCCT_CMAKE_FALLBACK=OFF
	-DBoost_NO_BOOST_CMAKE=ON
)
run_attempt() { # run_attempt <n> <extra cmake args...>
	local n="$1"; shift
	local bdir="$WORK/configure-a$n"
	rm -rf "$bdir"
	echo "== configure attempt $n (log: configure-attempt$n.log)"
	cmake -S "$SRCFC" -B "$bdir" -G Ninja "${SYNTH[@]}" "$@" \
		> "$DIST/configure-attempt$n.log" 2>&1
	echo "   attempt $n exit: $? (0 = configure complete)"
	grep -m1 "Set up to compile with Qt" "$DIST/configure-attempt$n.log" || true
	tail -4 "$DIST/configure-attempt$n.log" || true
}
qt_reached() { grep -q "Set up to compile with Qt" "$DIST/configure-attempt$1.log" 2>/dev/null; }
cfg_done() { grep -q "Generating done" "$DIST/configure-attempt$1.log" 2>/dev/null; }

run_attempt 1
if ! cfg_done 1; then
	# A2 seeds ([CONFIG], feedstock-style).
	SEEDS=()
	[ -f "$PREFIX/include/python3.13/Python.h" ] && SEEDS+=(
		-DPython3_EXECUTABLE="$(command -v python3)"
		-DPython3_INCLUDE_DIR="$PREFIX/include/python3.13"
		-DPython3_LIBRARY="$PREFIX/Python.xcframework/ios-arm64/Python.framework/Python")
	[ -f "$IOS_SDK_PATH/usr/lib/libicucore.tbd" ] && SEEDS+=(
		-DICU_INCLUDE_DIR="$IOS_SDK_PATH/usr/include"
		-DICU_UC_LIBRARIES="$IOS_SDK_PATH/usr/lib/libicucore.tbd"
		-DICU_I18N_LIBRARIES="$IOS_SDK_PATH/usr/lib/libicucore.tbd")
	[ -d "$PREFIX/include/opencascade" ] && \
		SEEDS+=(-DOCC_INCLUDE_DIR="$PREFIX/include/opencascade")
	run_attempt 2 "${SEEDS[@]}"
fi
if ! cfg_done 1 && ! cfg_done 2 && ! qt_reached 2; then
	# A3: bypass the pre-Qt SMESH/VTK wall + seed OpenGL/GLU.
	SEEDS3=()
	[ -f "$PREFIX/include/python3.13/Python.h" ] && SEEDS3+=(
		-DPython3_EXECUTABLE="$(command -v python3)"
		-DPython3_INCLUDE_DIR="$PREFIX/include/python3.13"
		-DPython3_LIBRARY="$PREFIX/Python.xcframework/ios-arm64/Python.framework/Python")
	[ -f "$IOS_SDK_PATH/usr/lib/libicucore.tbd" ] && SEEDS3+=(
		-DICU_INCLUDE_DIR="$IOS_SDK_PATH/usr/include"
		-DICU_UC_LIBRARIES="$IOS_SDK_PATH/usr/lib/libicucore.tbd"
		-DICU_I18N_LIBRARIES="$IOS_SDK_PATH/usr/lib/libicucore.tbd")
	[ -d "$PREFIX/include/opencascade" ] && \
		SEEDS3+=(-DOCC_INCLUDE_DIR="$PREFIX/include/opencascade")
	run_attempt 3 "${SEEDS3[@]}" \
		-DBUILD_FEM=OFF -DBUILD_MESH_PART=OFF -DBUILD_FEM_NETGEN=OFF \
		-DOPENGL_INCLUDE_DIR="$IOS_SDK_PATH/usr/include" \
		-DOPENGL_gl_LIBRARY="$WORK/glstub/libGL.a" \
		-DOPENGL_glu_LIBRARY="$WORK/glstub/libGLU.a"
fi

# ------------------------------------------------------- 6. classify
echo "== classification"
python3 "$ROOT/Scripts/classify-qt-gate.py" --dist "$DIST" --src "$SRCFC" || true
echo "== probe done: $(cat "$DIST/verdict.txt" 2>/dev/null | head -1)"
exit 0
