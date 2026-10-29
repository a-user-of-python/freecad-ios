#!/bin/bash
# S5 — Data layer (REAL stage): HDF5 1.14.6 + libmed 4.1.0 + the VTK
# subset SMESH needs + FreeCAD's bundled SMESH 7.7.1.0, all static
# iOS arm64, packaged as dist/iosdeps-data-$DEPS_HASH.tar.zst
# containing ios-prefix/.
#
# What the pinned sources actually require (established 2026-10-29 by
# reading src/3rdParty/salomesmesh in the pinned tarball — synthesis
# appendix item 2 left these open):
#
# * Bundled SMESH version is 7.7.1.0 (salomesmesh/CMakeLists.txt and
#   cMake/FreeCAD_Helpers/SetupSalomeSMESH.cmake agree) — SALOME 7.7-era
#   code FreeCAD carries in-tree, NOT the external SALOME 9.9 package
#   (conda smesh 9.9.0.0, which itself ships with NO HDF5 and NO
#   libmed in its dependency list — MED is off there).
# * MED driver IS compiled in by default: DriverMED_* and MED_*
#   wrapper sources sit inside src/SMESH/ and are globbed into the
#   SMESH target; SMESH_Mesh::MEDToMesh/ExportMED call them
#   unconditionally; there is no CMake option in the bundled tree to
#   switch MED off. The MED stack is two-layer: the in-tree wrapper
#   speaks HDF5 directly (MED_Common.hxx includes <hdf5.h>), and
#   MED_Factory.cpp / MED_V2_2_Wrapper.cpp additionally call libmed
#   (<med.h>, MEDfileOpen) for version detection and MED 2.2 files.
#   FreeCAD's own setup mirrors this: find_package(MEDFile REQUIRED)
#   whenever the bundled SMESH is used.
# * SMDS is built ON VTK: SMDS_Mesh stores its data in a
#   vtkUnstructuredGrid; 16 salomesmesh files include VTK headers
#   unguarded. The VTK surface SMESH names is exactly: CommonCore,
#   CommonDataModel, IOLegacy (vtkUnstructuredGridWriter) and
#   FiltersVerdict (vtkMeshQuality) — this stage builds that subset
#   of the pinned VTK 9.7.0 (it overlaps S6's larger FEM subset by
#   design; S7 merges prefixes of the same VTK version).
# * MEFISTO2 needs NO Fortran and NO f2c run: the tree ships
#   src/MEFISTO2/trte.f AND its f2c translation trte.c (header:
#   "translated by f2c (version 20100827)", hand-trimmed in 2014 so
#   the Fortran I/O calls are commented out and no libf2c is needed
#   at link), and salomesmesh/CMakeLists.txt compiles trte.c. The
#   route was re-proven on the host 2026-10-29: f2c 20200916
#   translates the shipped trte.f cleanly and clang compiles the
#   result with an identical symbol surface.
#
# Build order in this script:
#   0. Pull the REAL iosdeps-foundations / iosdeps-occt artifacts
#      (newest successful runs) via the GitHub API — foundations
#      supplies zlib + Boost, OCCT is a hard input. Fallbacks:
#      zlib+Boost are rebuilt in-stage if foundations is absent
#      (reported); OCCT absent = fail fast (SMESH cannot configure
#      without it; re-dispatch when deps-occt is green).
#   1. HDF5 1.14.6: host (macOS) build first — 1.14.6 retired the
#      H5detect/H5make_libsettings execution model (type init is
#      checked-in source; H5build_settings.c is a configure_file
#      template), so the cross ceremony that remains is its try_run
#      conversion tests. The host build harvests their exact results
#      for Apple arm64; the iOS target build is then configured
#      with CMAKE_CROSSCOMPILING + those values pre-seeded (the
#      H5ConversionTests macro skips any test whose result variable
#      is already defined). Seeded values are asserted against the
#      host build's cache in the log.
#   2. VTK 9.7.0 subset (wrapping OFF, so VTK's own
#      CMake/vtkCrossCompiling.cmake does not require host compile
#      tools for this module set).
#   3. libmed 4.1.0 (med-fichier, Debian orig source — the
#      salome-platform download endpoints refuse this sandbox's
#      egress; the Debian pool tarball is byte-pinned by sha256
#      below). Fortran auto-skips: med's CMake only enables the
#      Fortran API if a Fortran compiler exists, and none does for
#      iOS. Static libs only, tests/doc/python off.
#   4. Bundled SMESH via the superproject in
#      Scripts/data-patches/smesh-superproject-CMakeLists.txt +
#      the numbered patches in Scripts/data-patches/ (applied to
#      the extracted copy only; the pinned tarball is untouched),
#      including an iOS-arm64 link probe (SMESH_Gen construction)
#      that resolves the whole static set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/data"
PREFIX="$ROOT/ios-prefix"
SRCDIR="$WORK/src"
DIST="$ROOT/dist"
DEPS_HASH="${DEPS_HASH:-local}"
DEPS_PREFIX="$WORK/deps-prefix"
mkdir -p "$WORK" "$SRCDIR" "$DIST" "$DEPS_PREFIX"
rm -rf "$PREFIX"; mkdir -p "$PREFIX"

command -v zstd >/dev/null || brew install zstd

# ---------------------------------------------------------- 0. deps artifacts
# fetch_artifact <workflow-file> <artifact-name-prefix> <dest-dir>
# On success: extracts the artifact's *.tar.zst (an ios-prefix/ tree)
# into <dest-dir> and echoes "<run_id> <artifact_name>".
fetch_artifact() {
	local wf="$1" prefix_name="$2" dest="$3"
	[ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] || return 1
	local sel
	sel="$(python3 - "$wf" "$prefix_name" <<'PYEOF'
import json, os, sys, urllib.request
wf, prefix = sys.argv[1], sys.argv[2]
repo = os.environ["GITHUB_REPOSITORY"]; token = os.environ["GH_TOKEN"]
def get(url):
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)
try:
    runs = get(f"https://api.github.com/repos/{repo}/actions/workflows/{wf}/runs?status=success&per_page=8")["workflow_runs"]
    for run in runs:
        arts = get(f"https://api.github.com/repos/{repo}/actions/runs/{run['id']}/artifacts")["artifacts"]
        for a in arts:
            if a["name"].startswith(prefix) and not a["expired"]:
                print(run["id"], a["id"], a["name"]); sys.exit(0)
except Exception as e:
    print("fetch_artifact selection failed:", e, file=sys.stderr)
sys.exit(1)
PYEOF
)" || return 1
	local run_id art_id art_name
	run_id="$(echo "$sel" | awk '{print $1}')"
	art_id="$(echo "$sel" | awk '{print $2}')"
	art_name="$(echo "$sel" | awk '{print $3}')"
	echo "== downloading artifact $art_name (run $run_id, id $art_id)" >&2
	curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
		-H "Accept: application/vnd.github+json" \
		-o "$WORK/artifact.zip" \
		"https://api.github.com/repos/$GITHUB_REPOSITORY/actions/artifacts/$art_id/zip"
	rm -rf "$WORK/artifact-x"; mkdir -p "$WORK/artifact-x"
	python3 -m zipfile -e "$WORK/artifact.zip" "$WORK/artifact-x"
	local zst
	zst="$(find "$WORK/artifact-x" -name "*.tar.zst" | head -1)"
	[ -n "$zst" ] || return 1
	zstd -d -c "$zst" | tar -xf - -C "$WORK/artifact-x"
	[ -d "$WORK/artifact-x/ios-prefix" ] || return 1
	mkdir -p "$dest"
	cp -R "$WORK/artifact-x/ios-prefix/." "$dest/"
	rm -rf "$WORK/artifact-x" "$WORK/artifact.zip"
	echo "$run_id $art_name"
}

FOUNDATIONS_FROM="own-build (no usable iosdeps-foundations artifact)"
OCCT_FROM=""
if out="$(fetch_artifact deps-foundations.yml iosdeps-foundations- "$DEPS_PREFIX")"; then
	FOUNDATIONS_FROM="artifact: $out"
fi
if out="$(fetch_artifact deps-occt.yml iosdeps-occt- "$DEPS_PREFIX")"; then
	OCCT_FROM="artifact: $out"
else
	echo "ERROR: no usable iosdeps-occt artifact yet — SMESH cannot" >&2
	echo "       configure without the OCCT prefix. Re-dispatch" >&2
	echo "       deps-data.yml once deps-occt.yml is green." >&2
	exit 1
fi
echo "== foundations source: $FOUNDATIONS_FROM"
echo "== occt source: $OCCT_FROM"
test -f "$DEPS_PREFIX/lib/libTKernel.a"
lipo -info "$DEPS_PREFIX/lib/libTKernel.a" | grep -q arm64
echo "== OCCT prefix OK (libTKernel.a arm64, $(ls "$DEPS_PREFIX"/lib/libTK*.a | wc -l | tr -d ' ') toolkit archives)"

# shellcheck source=qt-install.inc.sh
. "$ROOT/Scripts/qt-install.inc.sh"

NCPU="$(sysctl -n hw.ncpu)"
TOOLCHAIN="$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake"
COMMON=(
	-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
	-DQT_HOST_PATH="$QT_DESKTOP"
	-DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
	-DCMAKE_INSTALL_PREFIX="$PREFIX"
	-DCMAKE_PREFIX_PATH="$PREFIX;$DEPS_PREFIX;$QT_IOS"
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

verify_lib() { # verify_lib <label> <lib-file> <symbol-regex>
	local label="$1" lib="$2" sym="$3"
	echo "== verifying $label: $lib"
	test -f "$lib" || { echo "ERROR: $label archive missing: $lib" >&2; exit 1; }
	lipo -info "$lib" | tee "$WORK/verify-$label.txt"
	grep -q "arm64" "$WORK/verify-$label.txt" || { echo "ERROR: $label is not arm64" >&2; exit 1; }
	nm "$lib" > "$WORK/nm-$label.txt" 2>/dev/null || true
	grep -q "$sym" "$WORK/nm-$label.txt" || { echo "ERROR: $label symbol '$sym' not found" >&2; exit 1; }
	echo "   OK (arm64, symbol $sym present)"
}

# ------------------------------------- foundations fallback (zlib + Boost)
# Only when the real foundations artifact was not available: rebuild
# the two pieces S5 consumes (zlib 1.3.1; Boost headers + compiled
# thread/date_time/etc. via the CMake superproject route, same as
# build-foundations.sh) into the deps prefix, and say so in the report.
if [ ! -f "$DEPS_PREFIX/lib/libz.a" ]; then
	echo "== foundations artifact absent: building zlib 1.3.1 in-stage"
	fetch "https://github.com/madler/zlib/archive/refs/tags/v1.3.1.tar.gz" "zlib-1.3.1"
	cmake -S "$SRCDIR/zlib-1.3.1" -B "$WORK/build-zlib" -G Ninja \
		"${COMMON[@]}" -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX"
	cmake --build "$WORK/build-zlib" -j"$NCPU" --target zlibstatic
	ZLIB_A="$(find "$WORK/build-zlib" -name "*.a" | head -1)"
	test -n "$ZLIB_A"
	mkdir -p "$DEPS_PREFIX/include" "$DEPS_PREFIX/lib"
	cp "$ZLIB_A" "$DEPS_PREFIX/lib/libz.a"
	cp "$SRCDIR/zlib-1.3.1/zlib.h" "$DEPS_PREFIX/include/zlib.h"
	cp "$WORK/build-zlib/zconf.h" "$DEPS_PREFIX/include/zconf.h"
fi
if [ ! -f "$DEPS_PREFIX/lib/libboost_thread.a" ]; then
	echo "== foundations artifact absent: building Boost 1.88.0 (thread set) in-stage"
	fetch "https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz" "boost_1_88_0"
	cmake -S "$SRCDIR/boost_1_88_0" -B "$WORK/build-boost" -G Ninja \
		"${COMMON[@]}" -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
		-DBOOST_INCLUDE_LIBRARIES="thread;date_time" -DBOOST_ENABLE_CMAKE=ON
	cmake --build "$WORK/build-boost" -j"$NCPU"
	cmake --install "$WORK/build-boost"
fi
verify_lib "deps-zlib" "$DEPS_PREFIX/lib/libz.a" "zlibVersion"
verify_lib "deps-boost-thread" "$DEPS_PREFIX/lib/libboost_thread.a" "thread"

# ---------------------------------------------------------- HDF5 1.14.6
# sha256 of the GitHub release tarball (verified locally 2026-10-29).
HDF5_URL="https://github.com/HDFGroup/hdf5/releases/download/hdf5_1.14.6/hdf5-1.14.6.tar.gz"
HDF5_SHA256="e4defbac30f50d64e1556374aa49e574417c9e72c6b1de7a4ff88c4b1bea6e9b"
if [ ! -d "$SRCDIR/hdf5-1.14.6" ]; then
	echo "== fetching HDF5 1.14.6"
	curl -fsSL --retry 3 -o "$WORK/hdf5.tar.gz" "$HDF5_URL"
	echo "$HDF5_SHA256  $WORK/hdf5.tar.gz" | shasum -a 256 -c -
	rm -rf "$SRCDIR/.extract"; mkdir -p "$SRCDIR/.extract"
	tar -xzf "$WORK/hdf5.tar.gz" -C "$SRCDIR/.extract"
	mv "$SRCDIR/.extract/hdf5-1.14.6" "$SRCDIR/hdf5-1.14.6"
	rm -rf "$SRCDIR/.extract" "$WORK/hdf5.tar.gz"
fi
HDF5_SRC="$SRCDIR/hdf5-1.14.6"

echo "== HDF5 host build (macOS native — harvests try-run results)"
cmake -S "$HDF5_SRC" -B "$WORK/build-hdf5-host" -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
	-DHDF5_BUILD_TOOLS=OFF -DHDF5_BUILD_EXAMPLES=OFF \
	-DHDF5_BUILD_CPP_LIB=OFF -DHDF5_BUILD_FORTRAN=OFF \
	-DHDF5_BUILD_JAVA=OFF -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
	-DHDF5_ENABLE_SZIP_SUPPORT=OFF
cmake --build "$WORK/build-hdf5-host" -j"$NCPU"

# The try_run-derived results (config/cmake/ConfigureChecks.cmake,
# H5ConversionTests + the _Float16 conversion set). Any of these left
# undefined in a cross configure either re-runs (impossible) or takes
# a wrong default; all are harvested from the host cache — Apple
# arm64 macOS and iOS agree on every one (same CPU, same clang FP
# semantics).
SEED_VARS=(
	H5_LDOUBLE_TO_LONG_SPECIAL
	H5_LONG_TO_LDOUBLE_SPECIAL
	H5_LDOUBLE_TO_LLONG_ACCURATE
	H5_LLONG_TO_LDOUBLE_CORRECT
	H5_DISABLE_SOME_LDOUBLE_CONV
	H5_FLOAT16_CONVERSION_FUNCS_LINK
	H5_FLOAT16_CONVERSION_FUNCS_LINK_NO_FLAGS
	H5_LDOUBLE_TO_FLOAT16_CORRECT
	H5_LDOUBLE_TO_FLOAT16_CORRECT_NO_FLAGS
)
SEED_ARGS=()
for v in "${SEED_VARS[@]}"; do
	line="$(grep "^${v}:INTERNAL=" "$WORK/build-hdf5-host/CMakeCache.txt" || true)"
	if [ -n "$line" ]; then
		val="${line#*=}"
		SEED_ARGS+=("-D${v}=${val}")
		echo "   seed $v = '${val}' (host cache)"
	else
		echo "   seed $v: not in host cache (test not applicable on this platform — left unset)"
	fi
done

echo "== HDF5 target build (iOS arm64, cross, pre-seeded)"
cmake -S "$HDF5_SRC" -B "$WORK/build-hdf5" -G Ninja "${COMMON[@]}" \
	-DCMAKE_CROSSCOMPILING=ON \
	-DBUILD_TESTING=OFF \
	-DHDF5_BUILD_TOOLS=OFF -DHDF5_BUILD_EXAMPLES=OFF \
	-DHDF5_BUILD_CPP_LIB=OFF -DHDF5_BUILD_FORTRAN=OFF \
	-DHDF5_BUILD_JAVA=OFF -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
	-DHDF5_ENABLE_SZIP_SUPPORT=OFF \
	-DZLIB_INCLUDE_DIR="$DEPS_PREFIX/include" \
	-DZLIB_LIBRARY="$DEPS_PREFIX/lib/libz.a" \
	-DZLIB_LIBRARY_RELEASE="$DEPS_PREFIX/lib/libz.a" \
	"${SEED_ARGS[@]}"
cmake --build "$WORK/build-hdf5" -j"$NCPU"
cmake --install "$WORK/build-hdf5"
HDF5_A="$(find "$PREFIX/lib" -name "libhdf5.a" | head -1)"
test -n "$HDF5_A"
verify_lib "hdf5" "$HDF5_A" "H5Fcreate"
test -f "$PREFIX/include/hdf5.h"
grep -q "1.14.6" "$PREFIX/include/H5public.h" || grep -rq "1\.14\.6" "$PREFIX/include/H5version.h" || {
	echo "ERROR: installed HDF5 headers do not identify as 1.14.6" >&2; exit 1; }
echo "   OK (HDF5 1.14.6 headers installed)"

# ---------------------------------------------------------- VTK 9.7.0 subset
fetch "https://github.com/Kitware/VTK/archive/refs/tags/v9.7.0.tar.gz" "VTK-9.7.0"
echo "== configuring VTK subset (CommonCore, CommonDataModel, IOLegacy, FiltersVerdict + deps)"
cmake -S "$SRCDIR/VTK-9.7.0" -B "$WORK/build-vtk" -G Ninja "${COMMON[@]}" \
	-DVTK_BUILD_ALL_MODULES=OFF \
	-DVTK_MODULE_ENABLE_VTK_CommonCore=YES \
	-DVTK_MODULE_ENABLE_VTK_CommonDataModel=YES \
	-DVTK_MODULE_ENABLE_VTK_IOLegacy=YES \
	-DVTK_MODULE_ENABLE_VTK_FiltersVerdict=YES \
	-DVTK_ENABLE_WRAPPING=OFF -DVTK_WRAP_PYTHON=OFF -DVTK_WRAP_JAVA=OFF \
	-DVTK_WRAP_JAVASCRIPT=OFF -DVTK_BUILD_TESTING=OFF \
	-DVTK_BUILD_EXAMPLES=OFF -DVTK_USE_MPI=OFF \
	-DVTK_ENABLE_REMOTE_MODULES=OFF -DVTK_USE_X=OFF
cmake --build "$WORK/build-vtk" -j"$NCPU"
cmake --install "$WORK/build-vtk"
verify_lib "vtkCommonCore" "$(find "$PREFIX/lib" -name "libvtkCommonCore-*.a" | head -1)" "vtkObject"
verify_lib "vtkCommonDataModel" "$(find "$PREFIX/lib" -name "libvtkCommonDataModel-*.a" | head -1)" "vtkUnstructuredGrid"
verify_lib "vtkIOLegacy" "$(find "$PREFIX/lib" -name "libvtkIOLegacy-*.a" | head -1)" "vtkUnstructuredGridWriter"
verify_lib "vtkFiltersVerdict" "$(find "$PREFIX/lib" -name "libvtkFiltersVerdict-*.a" | head -1)" "vtkMeshQuality"
echo "== VTK modules installed:"
ls "$PREFIX"/lib/libvtk*.a | sed 's/^/   /'

# ---------------------------------------------------------- libmed 4.1.0
# med-fichier (the MEDFile library SMESH's MED_Factory/V2_2 wrapper
# links). Source: Debian pool orig tarball, byte-pinned (the
# salome-platform.org endpoints 403 this sandbox's egress and are
# not relied on). sha256 verified locally 2026-10-29.
MED_URL="https://deb.debian.org/debian/pool/main/m/med-fichier/med-fichier_4.1.0+repack.orig.tar.gz"
MED_SHA256="ef5420a8b9aa2db4477661814ce355939fbdbe5f540f943508defc292f0c3b1b"
if [ ! -d "$SRCDIR/med-fichier-4.1.0+repack" ]; then
	echo "== fetching libmed 4.1.0 (med-fichier, Debian orig)"
	curl -fsSL --retry 3 -o "$WORK/med.tar.gz" "$MED_URL"
	echo "$MED_SHA256  $WORK/med.tar.gz" | shasum -a 256 -c -
	rm -rf "$SRCDIR/.extract"; mkdir -p "$SRCDIR/.extract"
	tar -xzf "$WORK/med.tar.gz" -C "$SRCDIR/.extract"
	mv "$SRCDIR/.extract/med-fichier-4.1.0+repack" "$SRCDIR/med-fichier-4.1.0+repack"
	rm -rf "$SRCDIR/.extract" "$WORK/med.tar.gz"
fi
HDF5_CMAKE_DIR="$(find "$PREFIX/lib/cmake" -maxdepth 1 -type d -name "hdf5*" | head -1)"
echo "== configuring libmed (static, no tests/doc/python; HDF5 config at $HDF5_CMAKE_DIR)"
cmake -S "$SRCDIR/med-fichier-4.1.0+repack" -B "$WORK/build-med" -G Ninja "${COMMON[@]}" \
	-DMEDFILE_BUILD_TESTS=OFF -DMEDFILE_BUILD_SHARED_LIBS=OFF \
	-DMEDFILE_BUILD_STATIC_LIBS=ON -DMEDFILE_INSTALL_DOC=OFF \
	-DMEDFILE_BUILD_PYTHON=OFF -DMEDFILE_BUILD_DOC=OFF \
	-DHDF5_ROOT="$PREFIX" -DHDF5_ROOT_DIR="$PREFIX" \
	-DHDF5_DIR="$HDF5_CMAKE_DIR" \
	-DHDF5_INCLUDE_DIRS="$PREFIX/include" \
	-DHDF5_LIBRARIES="$PREFIX/lib/libhdf5.a"
cmake --build "$WORK/build-med" -j"$NCPU"
cmake --install "$WORK/build-med"
MED_A="$(find "$PREFIX/lib" -name "libmedC*.a" -o -name "libmed.a" | head -1)"
test -n "$MED_A"
verify_lib "libmed" "$MED_A" "MEDfileOpen"
ls "$PREFIX"/lib/libmed*.a | sed 's/^/   /'
test -f "$PREFIX/include/med.h"
echo "   OK (med.h installed)"

# ---------------------------------------------------------- SMESH 7.7.1.0 (bundled)
PIN_TARBALL_URL="$(grep 'Source tarball' "$ROOT/PIN.md" | grep -o 'https://[^`]*' | head -1)"
PIN_TARBALL_SHA="$(grep 'Tarball sha256' "$ROOT/PIN.md" | grep -o '[0-9a-f]\{64\}' | head -1)"
test -n "$PIN_TARBALL_URL" && test -n "$PIN_TARBALL_SHA"
SMESH_SRC="$WORK/smesh-src"
if [ ! -d "$SMESH_SRC/salomesmesh" ]; then
	echo "== fetching pinned FreeCAD tarball for salomesmesh"
	curl -fsSL --retry 3 -o "$WORK/freecad.tar.gz" "$PIN_TARBALL_URL"
	echo "$PIN_TARBALL_SHA  $WORK/freecad.tar.gz" | shasum -a 256 -c -
	mkdir -p "$SMESH_SRC"
	tar -xzf "$WORK/freecad.tar.gz" -C "$SMESH_SRC" \
		src/3rdParty/salomesmesh src/SMESH_Version.h.cmake
	mv "$SMESH_SRC/src/3rdParty/salomesmesh" "$SMESH_SRC/salomesmesh"
	mv "$SMESH_SRC/src/SMESH_Version.h.cmake" "$SMESH_SRC/SMESH_Version.h.cmake"
	rm -rf "$SMESH_SRC/src" "$WORK/freecad.tar.gz"
fi
echo "== salomesmesh census:"
grep -m4 "SMESH_VERSION_" "$SMESH_SRC/salomesmesh/CMakeLists.txt" | sed 's/^/   /'
find "$SMESH_SRC/salomesmesh/src" -name "*.cpp" | wc -l | sed 's/^/   cpp files: /'
ls "$SMESH_SRC/salomesmesh/src/MEFISTO2" | sed 's/^/   MEFISTO2: /'

echo "== applying data-patches"
for p in "$ROOT"/Scripts/data-patches/[0-9]*.patch; do
	[ -f "$p" ] || continue
	echo "   patch: $(basename "$p")"
	git -C "$SMESH_SRC" apply -p1 --whitespace=nowarn "$p"
done
cp "$ROOT/Scripts/data-patches/smesh-superproject-CMakeLists.txt" "$SMESH_SRC/CMakeLists.txt"

echo "== configuring SMESH (superproject)"
cmake -S "$SMESH_SRC" -B "$WORK/build-smesh" -G Ninja "${COMMON[@]}" \
	-DDEPS_PREFIX="$DEPS_PREFIX" -DDATA_PREFIX="$PREFIX"
echo "== building SMESH (+ link probe)"
cmake --build "$WORK/build-smesh" -j"$NCPU"
cmake --install "$WORK/build-smesh"
test -f "$WORK/build-smesh/smesh_link_probe"
echo "   OK (smesh_link_probe linked — full static set resolves)"
for lib in SMDS Driver DriverSTL DriverDAT DriverUNV SMESHDS SMESH MEFISTO2 StdMeshers; do
	verify_lib "smesh-$lib" "$PREFIX/lib/lib$lib.a" "."
done
nm "$PREFIX/lib/libSMESH.a" | grep -q "SMESH_Gen" || { echo "ERROR: libSMESH.a lacks SMESH_Gen" >&2; exit 1; }
nm "$PREFIX/lib/libSMESH.a" | grep -q "DriverMED" || { echo "ERROR: libSMESH.a lacks the MED driver" >&2; exit 1; }
nm "$PREFIX/lib/libMEFISTO2.a" | grep -q "f0trte_" || { echo "ERROR: libMEFISTO2.a lacks the f2c trte entry points" >&2; exit 1; }
nm "$PREFIX/lib/libStdMeshers.a" | grep -q "StdMeshers_Regular_1D" || { echo "ERROR: libStdMeshers.a lacks StdMeshers_Regular_1D" >&2; exit 1; }
echo "   OK (SMESH hallmark symbols: SMESH_Gen, DriverMED, f0trte_, StdMeshers_Regular_1D)"
ls -lh "$PREFIX"/lib/libSM*.a "$PREFIX"/lib/libDriver*.a "$PREFIX"/lib/libMEFISTO2.a "$PREFIX"/lib/libStdMeshers.a | sed 's/^/   /'
test -f "$PREFIX/include/salomesmesh/SMESH_Gen.hxx"
test -f "$PREFIX/include/salomesmesh/SMESH_Version.h"

# ---------------------------------------------------------- package
echo "== installed data-layer tree (libs):"
find "$PREFIX/lib" -name "*.a" | sort | sed 's/^/   /'
TARBALL="$DIST/iosdeps-data-$DEPS_HASH.tar.zst"
rm -f "$TARBALL"
tar -cf - -C "$ROOT" ios-prefix | zstd -19 -f -o "$TARBALL"
ls -lh "$TARBALL"
{
	echo "S5 data layer — report"
	echo "Qt (toolchain): $QT_VERSION (ios kit $QT_IOS, host $QT_DESKTOP)"
	echo "Prefix: ios-prefix/ (static, iOS arm64, deployment target 17.0)"
	echo "Inputs: foundations [$FOUNDATIONS_FROM]; OCCT [$OCCT_FROM]"
	echo "HDF5 1.14.6 (static, C only, zlib filter on): host build harvested"
	echo "  try-run conversion results; target build cross with pre-seeded values."
	echo "VTK 9.7.0 subset for SMESH: CommonCore, CommonDataModel, IOLegacy,"
	echo "  FiltersVerdict (+ CMake-resolved module deps); wrapping OFF."
	echo "libmed (MEDFile) 4.1.0 static (Debian orig source, sha256-pinned);"
	echo "  Fortran API auto-skipped (no Fortran compiler for iOS)."
	echo "SMESH: FreeCAD bundled salomesmesh 7.7.1.0 from the pinned tarball,"
	echo "  MED driver compiled in (in-tree HDF5 wrapper + libmed), MEFISTO2"
	echo "  from the shipped f2c trte.c (no Fortran), NETGENPlugin OFF."
	echo "  Superproject + patches: Scripts/data-patches/ (0001 static libs)."
	echo "  Link probe smesh_link_probe built and linked for iOS arm64."
	echo "Tarball: dist/iosdeps-data-$DEPS_HASH.tar.zst"
} | tee "$DIST/data-report.txt"
echo "== S5 done"
