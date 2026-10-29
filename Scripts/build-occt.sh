#!/bin/bash
# S2 — OCCT 8.0.1 full toolkit set for FreeCAD (REAL stage).
#
# Source: the cascade-ios repo at the commit pinned in PIN.md — its
# OCCT/src staging (the MetalCAD-proven 23-toolkit subset extended
# additively to the 35 toolkits of FreeCAD's configured census:
# ${OCC_LIBRARIES} + ${OCC_OCAF_LIBRARIES} + transitive closure).
# OCCT sources are NEVER modified (LGPL rule): this stage compiles
# the staged tree exactly as it stands.
#
# Build method mirrors cascade-ios's own build (gen_project.py /
# CascadePort.xcodeproj): every package directory is a header search
# path, C++17 (gnu++17), exceptions + RTTI on, defines NDEBUG /
# No_Exception / OCCT_NO_PLUGINS / OCC_CONVERT_SIGNALS. The one
# difference is the product form: cascade links everything into a
# single archive for its app; FreeCAD's OCC config consumes one
# static library per toolkit, so this stage assembles libTK*.a per
# toolkit from the same per-toolkit FILES.cmake file enumeration
# the cascade staging was built with (the staging tree contains
# exactly those files, so a toolkit's sources = the compilable
# files under its directory).
#
# Optional-dependency configuration (same choices as cascade's
# proven iOS build, recorded here):
#   - HAVE_FREETYPE is NOT defined: TKService's Font_FTFont keeps
#     its upstream stub shape, exactly as in MetalCAD's shipping
#     build. (FreeCAD renders text through Qt/FreeType from the
#     foundations prefix, not through OCCT's FT glue.)
#   - HAVE_RAPIDJSON IS defined, with RapidJSON 1.1.0 headers
#     (header-only, no link dependency) so TKDEGLTF/TKRWMesh get
#     their real glTF JSON reader/writer instead of the stub.
#   - No TBB, no FFmpeg, no FreeImage (all upstream-guarded).
#
# Output: dist/iosdeps-occt-8.0.1-$DEPS_HASH.tar.zst containing
# ios-prefix/ (lib/libTK*.a x35 + include/opencascade/ headers).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/occt"
PREFIX="$ROOT/ios-prefix"
DIST="$ROOT/dist"
DEPS_HASH="${DEPS_HASH:-local}"
mkdir -p "$WORK" "$DIST"
rm -rf "$PREFIX"; mkdir -p "$PREFIX/lib" "$PREFIX/include/opencascade"

# ---------------------------------------------------------- source pin
# The cascade-ios commit is on the PIN.md row labelled
# 'cascade-ios commit' — parse that row.
CASCADE_COMMIT="$(grep 'cascade-ios commit' "$ROOT/PIN.md" | grep -o '[0-9a-f]\{40\}' | head -1)"
test -n "$CASCADE_COMMIT"
echo "== cascade-ios commit (from PIN.md): $CASCADE_COMMIT"

SRC="$WORK/cascade-ios"
if [ ! -d "$SRC/OCCT/src" ]; then
	echo "== cloning cascade-ios"
	git clone --quiet https://github.com/a-user-of-python/cascade-ios.git "$SRC"
fi
git -C "$SRC" fetch --quiet origin "$CASCADE_COMMIT" || git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet "$CASCADE_COMMIT"
git -C "$SRC" rev-parse HEAD

OCCT_SRC="$SRC/OCCT/src"
test -f "$SRC/OCCT/LICENSE_LGPL_21.txt"
test -f "$SRC/OCCT/OCCT_LGPL_EXCEPTION.txt"
grep -q 'OCC_VERSION_COMPLETE "8.0.1"' "$SRC/OCCT/generated/Standard_Version.hxx"
echo "== OCCT 8.0.1 staging confirmed (licence texts present, version header 8.0.1)"

# ---------------------------------------------------------- rapidjson 1.1.0 (headers)
RJ="$WORK/rapidjson-1.1.0"
if [ ! -d "$RJ/include/rapidjson" ]; then
	echo "== fetching RapidJSON 1.1.0 (header-only)"
	curl -fsSL --retry 3 -o "$WORK/rj.tar.gz" \
		"https://github.com/Tencent/rapidjson/archive/refs/tags/v1.1.0.tar.gz"
	rm -rf "$WORK/.rj"; mkdir -p "$WORK/.rj"
	tar -xzf "$WORK/rj.tar.gz" -C "$WORK/.rj"
	mv "$WORK/.rj/rapidjson-1.1.0" "$RJ"
	rm -rf "$WORK/.rj" "$WORK/rj.tar.gz"
fi

# ---------------------------------------------------------- toolchain
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TARGET="arm64-apple-ios17.0"
NCPU="$(sysctl -n hw.ncpu)"
echo "== iOS SDK: $SDK (target $TARGET, -j$NCPU)"

# Header search paths: every package directory of the staging tree
# (cascade's mechanism) + the generated-headers dir.
INCS=()
while IFS= read -r d; do INCS+=("-I$d"); done < <(find "$OCCT_SRC" -type d | sort)
INCS+=("-I$SRC/OCCT/generated" "-I$RJ/include")

DEFS=(-DNDEBUG -DNo_Exception -DOCCT_NO_PLUGINS -DOCC_CONVERT_SIGNALS -DHAVE_RAPIDJSON)
CXXFLAGS=(-std=gnu++17 -fexceptions -frtti -O2 -target "$TARGET" -isysroot "$SDK"
	-miphoneos-version-min=17.0 -w)
CFLAGS=(-O2 -target "$TARGET" -isysroot "$SDK" -miphoneos-version-min=17.0 -w)

# compile-one helper (parallelised with xargs -P)
cat > "$WORK/compile_one.sh" <<EOF
#!/bin/bash
# args: <src> <obj>
f="\$1"; o="\$2"
case "\$f" in
	*.c) exec clang ${CFLAGS[*]} ${DEFS[*]} ${INCS[*]} -c "\$f" -o "\$o" ;;
	*)   exec clang++ ${CXXFLAGS[*]} ${DEFS[*]} ${INCS[*]} -c "\$f" -o "\$o" ;;
esac
EOF
chmod +x "$WORK/compile_one.sh"

# ---------------------------------------------------------- the 35 toolkits
TOOLKITS=(
	TKernel TKMath TKG2d TKG3d TKGeomBase TKBRep TKGeomAlgo TKTopAlgo
	TKPrim TKBO TKShHealing TKBool TKHLR TKFeat TKMesh
	TKFillet TKOffset TKExpress TKService TKV3d TKMeshVS
	TKCDF TKLCAF TKCAF TKBinL TKBin TKVCAF
	TKXSBase TKDE TKDESTEP TKDEIGES TKDEGLTF TKDESTL TKXCAF TKRWMesh
)
echo "== expected toolkits: ${#TOOLKITS[@]}"
test "${#TOOLKITS[@]}" -eq 35

# Staging-tree census check: every toolkit directory present in the
# tree must be in the expected list and vice versa (no silent drift).
find "$OCCT_SRC" -mindepth 2 -maxdepth 2 -type d -exec basename {} \; | sort -u > "$WORK/tree-toolkits.txt"
printf '%s\n' "${TOOLKITS[@]}" | sort -u > "$WORK/expected-toolkits.txt"
diff "$WORK/expected-toolkits.txt" "$WORK/tree-toolkits.txt" || {
	echo "ERROR: staging tree toolkit set != expected 35" >&2; exit 1; }
echo "== staging tree toolkit set == expected 35"

for tk in "${TOOLKITS[@]}"; do
	tkdir="$(find "$OCCT_SRC" -mindepth 2 -maxdepth 2 -type d -name "$tk")"
	test -n "$tkdir"
	objdir="$WORK/obj/$tk"; mkdir -p "$objdir"
	echo "== building $tk"
	# Per-toolkit file enumeration = the compilable files under the
	# toolkit directory (the staging tree holds exactly the
	# FILES.cmake-enumerated set; see cascade-ios MANIFEST.md).
	find "$tkdir" -type f \( -name '*.cxx' -o -name '*.cpp' -o -name '*.c' \) | sort > "$WORK/$tk.sources"
	count="$(wc -l < "$WORK/$tk.sources" | tr -d ' ')"
	test "$count" -gt 0
	# Map each source to a unique object name, compile in parallel.
	: > "$WORK/$tk.jobs"
	i=0
	while IFS= read -r f; do
		i=$((i + 1))
		echo "$f $objdir/$(printf '%04d' "$i")-$(basename "$f").o" >> "$WORK/$tk.jobs"
	done < "$WORK/$tk.sources"
	if ! xargs -P "$NCPU" -n 2 "$WORK/compile_one.sh" < "$WORK/$tk.jobs" > "$WORK/$tk.build.log" 2>&1; then
		echo "ERROR: $tk failed to compile; last log lines:" >&2
		tail -n 40 "$WORK/$tk.build.log" >&2
		exit 1
	fi
	ar rcs "$PREFIX/lib/lib$tk.a" "$objdir"/*.o
	rm -rf "$objdir"
	echo "   $tk: $count sources -> lib$tk.a"
done

# Headers, flattened the way OCCT's own install lays them out
# (include/opencascade), plus the one generated header.
find "$OCCT_SRC" -type f \( -name '*.hxx' -o -name '*.lxx' -o -name '*.pxx' \
	-o -name '*.gxx' -o -name '*.h' \) -exec cp {} "$PREFIX/include/opencascade/" \;
cp "$SRC/OCCT/generated/Standard_Version.hxx" "$PREFIX/include/opencascade/"
mkdir -p "$PREFIX/share/occt-licence"
cp "$SRC/OCCT/LICENSE_LGPL_21.txt" "$SRC/OCCT/OCCT_LGPL_EXCEPTION.txt" "$PREFIX/share/occt-licence/"

# ---------------------------------------------------------- verification
echo "== verifying 35 arm64 archives + hallmark symbols"
fail=0
check_sym() { # check_sym <lib> <symbol-substring>
	if ! nm "$PREFIX/lib/lib$1.a" 2>/dev/null | grep -q "$2"; then
		echo "ERROR: lib$1.a missing hallmark symbol '$2'" >&2; fail=1
	fi
}
for tk in "${TOOLKITS[@]}"; do
	lib="$PREFIX/lib/lib$tk.a"
	test -f "$lib" || { echo "ERROR: missing $lib" >&2; fail=1; continue; }
	lipo -info "$lib" | grep -q "arm64" || { echo "ERROR: lib$tk.a is not arm64" >&2; fail=1; }
done
check_sym TKHLR HLRBRep_Algo
check_sym TKFeat BRepFeat
check_sym TKExpress Express
check_sym TKDEIGES IGESControl_Reader
check_sym TKDEGLTF RWGltf_CafReader
check_sym TKDESTL StlAPI
check_sym TKBin BinDrivers
check_sym TKBinL BinLDrivers
check_sym TKVCAF TPrsStd
check_sym TKMeshVS MeshVS
check_sym TKV3d V3d_View
check_sym TKRWMesh RWMesh
check_sym TKDESTEP STEPControl_Reader
check_sym TKernel Standard_Type
test "$fail" -eq 0
ls -lh "$PREFIX/lib"

# ---------------------------------------------------------- package
command -v zstd >/dev/null || brew install zstd
echo "== installed OCCT tree:"
find "$PREFIX" -type f | sort | sed 's/^/   /' | head -n 60
TARBALL="$DIST/iosdeps-occt-8.0.1-$DEPS_HASH.tar.zst"
rm -f "$TARBALL"
tar -cf - -C "$ROOT" ios-prefix | zstd -19 -f -o "$TARBALL"
ls -lh "$TARBALL"
{
	echo "S2 OCCT — report"
	echo "Source: cascade-ios @ $CASCADE_COMMIT (OCCT 8.0.1 staging, 35 toolkits)"
	echo "Prefix: ios-prefix/ (static, iOS arm64, deployment target 17.0)"
	echo "Toolkits (35): ${TOOLKITS[*]}"
	echo "Config: HAVE_RAPIDJSON (headers 1.1.0), HAVE_FREETYPE undefined (cascade parity), no TBB/FFmpeg/FreeImage"
	echo "Tarball: dist/iosdeps-occt-8.0.1-$DEPS_HASH.tar.zst"
} | tee "$DIST/occt-report.txt"
echo "== S2 done"
