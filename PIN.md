# PIN — frozen target for the FreeCAD iPad port

Everything a build consumes is recorded here before the build runs.
Upgrading any entry is a deliberate, separate change — never a side
effect of a rebuild. Resolution date: 2026-10-29 (values marked
RESOLVING are being confirmed against the live feedstock; research-time
values in brackets).

## FreeCAD source (Target B — dev-line weekly snapshot)

| Item | Value |
|---|---|
| Feedstock weekly version | RESOLVING [research time: 2026.09.16] |
| Source tarball | `https://github.com/FreeCAD/FreeCAD/releases/download/weekly-<version>/freecad_source_weekly-<version>.tar.gz` |
| Tarball sha256 | RESOLVING [2026.09.16: `1fba830dbb58c67c88222b375d336e721f03e728cdb0392b4080f6ef02fea0c4`] |
| FreeCAD `main` commit | RESOLVING |

### Submodule SHAs (at the pinned commit)

| Submodule | Path | SHA |
|---|---|---|
| AddonManager | `src/Mod/AddonManager` | RESOLVING |
| OndselSolver | `src/3rdParty/OndselSolver` | RESOLVING |
| GSL | `src/3rdParty/GSL` | RESOLVING |
| (test lib) | `tests/lib` | RESOLVING |

## Dependency versions (conda-forge pinning, Target B column)

| Dependency | Pinned version | Notes |
|---|---|---|
| OCCT | **8.0.1** | cascade-ios tree, extended to the full `${OCC_LIBRARIES}` set |
| Python | **3.13** (exact patch RESOLVING) | BeeWare XCFramework route; PEP 730 upstream build as fallback |
| Coin | **4.0.10** | against gl4es (graphics spike S4) |
| Boost | **1.90** | compiled libs only: program_options, regex, thread, date_time |
| SMESH | **9.9.0.0** | FreeCAD's bundled copy (`src/3rdParty/salomesmesh`) is primary |
| HDF5 | **1.14.6** | |
| VTK | **9.7.0** | subset only, FEM phases (stage S6); M4 builds `BUILD_FEM_VTK=OFF` |
| Xerces-C | **3.3** | built-in transcoder, no ICU |
| Eigen | **3.4** | header-only, copied |
| yaml-cpp | **0.8** | |
| FreeType | **2.x** (exact RESOLVING) | |
| pivy | **≥ 0.6.10** | ships with the GUI from M2 |
| fmt | vendored | `FREECAD_USE_EXTERNAL_FMT=OFF` |
| PCL | OFF | `FREECAD_USE_PCL=OFF` |

## Our toolchain pins

| Item | Value |
|---|---|
| Qt | **6.9.3** (primary; fallback 6.8.3) — dual-kit aqtinstall: mac desktop `clang_64` host tools + `mac ios` target; `FREECAD_QT_VERSION=6` forced |
| PySide / Shiboken | OFF for the shipping configuration (`FREECAD_USE_PYSIDE=OFF`, `FREECAD_USE_SHIBOKEN=OFF`, `FREECAD_CHECK_PYSIDE=OFF`) |
| cascade-ios commit | RESOLVING (HEAD at freeze; the OCCT extension lands on top) |
| Runner | `macos-26`, standard GitHub-hosted only |
| iOS deployment target | 17.0 |
| Python linking | `BUILD_DYNAMIC_LINK_PYTHON=OFF` |
