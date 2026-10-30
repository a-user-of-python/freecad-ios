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
#
# PHASE 2 (2026-10-29, full configure depth): foundations now carries
# a real iOS ICU 78.1 (run 40985309078) and deps-occt is REAL (run
# 40983737180, 35 libTK*.a). The ladder below is REPLACED by the
# Phase-2 ladder in section 5: every attempt uses the Stage-7 shape
# seeds (ICU->foundations prefix — mandatory, see INVENTORY; Python->
# BeeWare prefix; OCC->occt prefix; rcc zlib/9; GL/GLU probe stubs,
# labelled [CONFIG]) and differs only in the module set:
#        P2-A1 the LEAN set exactly as named in the plan of record
#              (Part, PartDesign, Sketcher, Spreadsheet, Mesh, Import;
#              everything else OFF, incl. Material/Draft/TechDraw)
#        P2-A2 the dependency-CLOSED lean set (A1 + Material, Draft,
#              TechDraw, Measure — the minimal closure demanded by
#              CheckInterModuleDependencies.cmake in the pinned tree)
#        P2-A3 A2's module set with BUILD_GUI=OFF (console shape —
#              isolates GUI-class vs core-class blockers if A2 stops)
# No FreeCAD sources are patched in this probe, ever.
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

# SDK recovery (run 40946217444 lesson): on that runner the inc's
# discovery returned EMPTY (xcode-select pointed at CommandLineTools;
# its `sort -Vr` scan is unreliable under BSD sort) and passing an
# explicit empty -DCMAKE_OSX_SYSROOT then poisoned the Qt toolchain's
# own SDK resolution — the battery configure fell back to the MacOSX
# SDK and Qt6Gui's GLESv2 check failed. Recover like build-occt.sh:
# reset xcode-select, rescan without sort -V, filesystem fallback.
if [ -z "${IOS_SDK_PATH:-}" ] || [ ! -d "$IOS_SDK_PATH" ]; then
	echo "== iPhoneOS SDK recovery (inc returned '${IOS_SDK_PATH:-empty}')"
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
	if [ -z "${IOS_SDK_PATH:-}" ] || [ ! -d "$IOS_SDK_PATH" ]; then
		found="$(find /Applications -maxdepth 7 -type d -name 'iPhoneOS*.sdk' 2>/dev/null | head -1)"
		[ -d "$found" ] && IOS_SDK_PATH="$found"
	fi
	export DEVELOPER_DIR IOS_SDK_PATH
	echo "   recovered SDK: '${IOS_SDK_PATH:-STILL EMPTY}'"
fi

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
	-DCMAKE_OSX_DEPLOYMENT_TARGET=17.0
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
)
# Pass the sysroot ONLY when a real SDK path was resolved — an
# explicit empty CMAKE_OSX_SYSROOT breaks qt.toolchain.cmake's own
# resolution and drops the configure onto the host SDK (run
# 40946217444 battery GLESv2 failure).
if [ -n "${IOS_SDK_PATH:-}" ] && [ -d "$IOS_SDK_PATH" ]; then
	COMMON+=(-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH")
fi

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
	# The weekly tarball is ROOT-FLAT (files at the top, no enclosing
	# directory) — do NOT --strip-components: run 40946217444 did and
	# deleted CMakeLists.txt itself, so attempt 1 configured an
	# empty tree.
	tar -xzf "$WORK/fc.tar.gz" -C "$SRCFC"
	rm -f "$WORK/fc.tar.gz"
fi
# Hard verification: a mangled tree must die HERE, loudly, not as a
# nonsense configure log downstream.
if [ ! -f "$SRCFC/CMakeLists.txt" ] || [ ! -f "$SRCFC/cMake/FreeCAD_Helpers/SetupQt.cmake" ]; then
	echo "ERROR: extracted source tree is incomplete (CMakeLists.txt / SetupQt.cmake missing under $SRCFC)" >&2
	ls "$SRCFC" | head -20 >&2 || true
	exit 1
fi
echo "== source extracted + verified (PIN commit a4ce44d33b7e42e16cb8156058a1894237042ab4)"

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
	if [ -f "$PREFIX/lib/libicuuc.a" ] && [ -f "$PREFIX/lib/libicui18n.a" ] && [ -d "$PREFIX/include/unicode" ]; then
		echo "icu: REAL (libicuuc.a + libicui18n.a + unicode/ headers in foundations prefix)";
	else echo "icu: MISSING"; fi
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
# yaml-cpp: same probe-local fill logic as fmt (foundations stages
# it, but foundations has not landed; SetupYamlCpp is the pinned
# configure's THIRD setup call, so filling it buys real depth —
# the next stops are then fmt (filled), ICU, Python (landed)).
if ! find "$PREFIX" -iname 'yaml-cpp-config.cmake' -o -iname 'yaml-cppConfig.cmake' 2>/dev/null | grep -q .; then
	echo "== probe-local fill: building yaml-cpp 0.8.0 into the prefix ([DEP] remediation)"
	YAMLD="$WORK/yaml-cpp-0.8.0"
	if [ ! -d "$YAMLD" ]; then
		curl -fsSL --retry 3 -o "$WORK/yaml.tar.gz" \
			"https://github.com/jbeder/yaml-cpp/archive/refs/tags/0.8.0.tar.gz"
		mkdir -p "$WORK/yamlsrc"; tar -xzf "$WORK/yaml.tar.gz" -C "$WORK/yamlsrc" --strip-components=1
		mv "$WORK/yamlsrc" "$YAMLD"
	fi
	cmake -S "$YAMLD" -B "$WORK/build-yaml" -G Ninja "${COMMON[@]}" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" -DYAML_CPP_BUILD_TESTS=OFF \
		-DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF \
		-DYAML_BUILD_SHARED_LIBS=OFF > "$DIST/yaml-build.log" 2>&1 \
		&& cmake --build "$WORK/build-yaml" -j"$(sysctl -n hw.ncpu)" >> "$DIST/yaml-build.log" 2>&1 \
		&& cmake --install "$WORK/build-yaml" >> "$DIST/yaml-build.log" 2>&1 \
		&& echo "   yaml-cpp installed" || echo "   yaml-cpp build FAILED (see yaml-build.log; configure will classify)"
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
SYSROOT_FLAG=()
[ -n "${IOS_SDK_PATH:-}" ] && [ -d "$IOS_SDK_PATH" ] && SYSROOT_FLAG=(-isysroot "$IOS_SDK_PATH")
xcrun clang -target arm64-apple-ios17.0 ${SYSROOT_FLAG[@]+"${SYSROOT_FLAG[@]}"} \
	-c "$WORK/glstub/empty.c" -o "$WORK/glstub/empty.o" 2>/dev/null || \
	clang -c "$WORK/glstub/empty.c" -o "$WORK/glstub/empty.o"
ar rcs "$WORK/glstub/libGL.a" "$WORK/glstub/empty.o"
ar rcs "$WORK/glstub/libGLU.a" "$WORK/glstub/empty.o"

# Direct host-rcc probe of FreeCAD's EXACT FREECAD_RCC_OPTIONS
# (zstd/19/70), non-fatal: run 40962937748 showed the official
# 6.9.3 host rcc lacks compiled-in zstd. Recorded for the
# classifier as a [CONFIG] item (remedy: FREECAD_RCC_COMPRESSION_ALGO
# =zlib, FreeCAD's own cache variable).
RCC_BIN="$(find "$QT_DESKTOP" -name rcc -type f 2>/dev/null | head -1)"
{
	echo "host rcc: $RCC_BIN"
	"$RCC_BIN" --compress-algo zstd --compress 19 --threshold 70 \
		--name qtgate_res_probe -o "$WORK/rcc-probe-out.cpp" \
		"$ROOT/Spike/QtGate/res.qrc" 2>&1
	echo "rcc exit: $?"
} > "$DIST/rcc-zstd-probe.log" 2>&1 || true
cat "$DIST/rcc-zstd-probe.log"

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
if [ -n "${IOS_SDK_PATH:-}" ] && [ -d "$IOS_SDK_PATH" ]; then
	SYNTH+=(-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH")
fi
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

# ---- PHASE-2 ladder (replaces the Phase-1 A2/A3 blocks) ----
# Stage-7 shape seeds, common to every Phase-2 attempt:
#  * rcc zlib/9 (Phase-1 [CONFIG] finding; host rcc has no zstd)
#  * ICU -> foundations prefix (MANDATORY per INVENTORY: without
#    ICU_INCLUDE_DIR seeded to the prefix, FindICU mixes SDK
#    libicucore headers with the prefix's renamed libraries)
#  * Python -> BeeWare prefix; OCC -> occt prefix
#  * OpenGL/GLU -> probe stub archives ([CONFIG] seed; iOS has no
#    GLU — the real companion GLU is S4 scope; SetupOpenGL fatals
#    pre-Qt without a GLU library)
SYNTH+=(
	-DFREECAD_RCC_COMPRESSION_ALGO=zlib
	-DFREECAD_RCC_COMPRESSION_LEVEL=9
)
P2SEEDS=()
[ -f "$PREFIX/include/python3.13/Python.h" ] && P2SEEDS+=(
	-DPython3_EXECUTABLE="$(command -v python3)"
	-DPython3_INCLUDE_DIR="$PREFIX/include/python3.13"
	-DPython3_LIBRARY="$PREFIX/Python.xcframework/ios-arm64/Python.framework/Python")
[ -f "$PREFIX/lib/libicuuc.a" ] && P2SEEDS+=(
	-DICU_ROOT="$PREFIX"
	-DICU_INCLUDE_DIR="$PREFIX/include"
	-DICU_INCLUDE_DIRS="$PREFIX/include")
[ -d "$PREFIX/include/opencascade" ] && \
	P2SEEDS+=(-DOCC_INCLUDE_DIR="$PREFIX/include/opencascade")
[ -n "${IOS_SDK_PATH:-}" ] && [ -d "$IOS_SDK_PATH" ] && P2SEEDS+=(
	-DOPENGL_INCLUDE_DIR="$IOS_SDK_PATH/usr/include"
	-DOPENGL_gl_LIBRARY="$WORK/glstub/libGL.a"
	-DOPENGL_glu_LIBRARY="$WORK/glstub/libGLU.a")
# The LEAN module set (plan of record 2026-10-29): Part, PartDesign,
# Sketcher, Spreadsheet, Mesh, Import ON; FEM and the rest OFF.
LEAN_EXACT=(
	-DBUILD_PART=ON -DBUILD_PART_DESIGN=ON -DBUILD_SKETCHER=ON
	-DBUILD_SPREADSHEET=ON -DBUILD_MESH=ON -DBUILD_IMPORT=ON
	-DBUILD_FEM=OFF -DBUILD_FEM_NETGEN=OFF -DBUILD_MESH_PART=OFF
	-DBUILD_FLAT_MESH=OFF -DBUILD_ADDONMGR=OFF -DBUILD_BIM=OFF
	-DBUILD_DRAFT=OFF -DBUILD_HELP=OFF -DBUILD_INSPECTION=OFF
	-DBUILD_JTREADER=OFF -DBUILD_MATERIAL=OFF
	-DBUILD_MATERIAL_EXTERNAL=OFF -DBUILD_OPENSCAD=OFF
	-DBUILD_CAM=OFF -DBUILD_ASSEMBLY=OFF -DBUILD_PLOT=OFF
	-DBUILD_POINTS=OFF -DBUILD_REVERSEENGINEERING=OFF
	-DBUILD_ROBOT=OFF -DBUILD_SHOW=OFF -DBUILD_START=OFF
	-DBUILD_TEMPLATE=OFF -DBUILD_TEST=OFF -DBUILD_MEASURE=OFF
	-DBUILD_TECHDRAW=OFF -DBUILD_TUX=OFF -DBUILD_WEB=OFF
	-DBUILD_SURFACE=OFF
)
# Dependency closure demanded by the pinned tree's
# CheckInterModuleDependencies.cmake: Part->Material,
# Spreadsheet->Draft, Draft->Sketcher+TechDraw,
# TechDraw->Part+PartDesign+Spreadsheet+Measure+Import.
LEAN_CLOSED=(
	-DBUILD_MATERIAL=ON -DBUILD_DRAFT=ON -DBUILD_TECHDRAW=ON
	-DBUILD_MEASURE=ON
)
# bash 3.2 (macOS /bin/bash) + set -u: "${arr[@]}" on an EMPTY array
# is a fatal unbound-variable — use the ${arr[@]+...} idiom.
run_attempt 1 ${P2SEEDS[@]+"${P2SEEDS[@]}"} "${LEAN_EXACT[@]}"
if ! cfg_done 1; then
	run_attempt 2 ${P2SEEDS[@]+"${P2SEEDS[@]}"} \
		"${LEAN_EXACT[@]}" "${LEAN_CLOSED[@]}"
fi
if ! cfg_done 1 && ! cfg_done 2; then
	# Console shape: same closed-lean modules, BUILD_GUI=OFF —
	# isolates GUI-class vs core-class blockers.
	run_attempt 3 ${P2SEEDS[@]+"${P2SEEDS[@]}"} \
		"${LEAN_EXACT[@]}" "${LEAN_CLOSED[@]}" -DBUILD_GUI=OFF
fi

# ------------------------------------------------------- 6. classify
echo "== classification"
python3 "$ROOT/Scripts/classify-qt-gate.py" --dist "$DIST" --src "$SRCFC" || true
echo "== probe done: $(cat "$DIST/verdict.txt" 2>/dev/null | head -1)"
exit 0
