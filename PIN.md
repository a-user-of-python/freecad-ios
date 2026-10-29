# PIN — frozen target for the FreeCAD iPad port

Everything a build consumes is recorded here before the build runs.
Upgrading any entry is a deliberate, separate change — never a side
effect of a rebuild. **Frozen 2026-10-29** from the live conda-forge
feedstock + pinning (resolution record:
`hidden_files/pin-resolution.md` in the goal workspace).

## FreeCAD source (Target B — dev-line weekly snapshot)

| Item | Value |
|---|---|
| Feedstock weekly version | **2026.09.16** (feedstock `main` HEAD `0b1c3b9f700f68ab80589eacbcacd3998914793a`; upstream has newer weeklies — the feedstock version is the pin of record) |
| Source tarball | `https://github.com/FreeCAD/FreeCAD/releases/download/weekly-2026.09.16/freecad_source_weekly-2026.09.16.tar.gz` |
| Tarball size | 114,048,430 bytes |
| Tarball sha256 | `1fba830dbb58c67c88222b375d336e721f03e728cdb0392b4080f6ef02fea0c4` (verified: computed == feedstock recipe == release SHA256 asset) |
| FreeCAD `main` commit | `a4ce44d33b7e42e16cb8156058a1894237042ab4` (tag `weekly-2026.09.16` is a lightweight tag pointing directly at this commit; tree `a6136de448300c69a8dbac6efb8bcf736363e69c`) |

The tarball is self-contained: all submodule directories are populated
in it. SHAs below are the gitlinks at the pinned commit, recorded for
any future git-based fetch.

### Submodule SHAs (at the pinned commit)

| Submodule | Path | SHA |
|---|---|---|
| AddonManager | `src/Mod/AddonManager` | `c418bc9e28980f3254e6433454f170acfdc204c0` |
| OndselSolver | `src/3rdParty/OndselSolver` | `3afcb30353084d402e3c34760cd662cf22d88759` |
| GSL | `src/3rdParty/GSL` | `543d0dd3fe966ddf20e884b44e5fdbf12cb43784` |
| Coin (vendored) | `src/3rdParty/coin` | `e9f1234a22e39e751675807d9b4af657b34dac20` |
| pivy (vendored) | `src/3rdParty/pivy` | `515f038d32f163a976acd8a8cd9e8d26e1d0b884` |
| tests/lib | — | **does not exist at this snapshot** (no gitlink, not in `.gitmodules`) |

## Dependency versions (conda-forge pinning snapshot, resolved 2026-10-29)

Pinning feedstock HEAD `7c11f837d5cd7a0fbd13254f36e0ba4183e8b61e`.

| Dependency | Pinned version | Notes |
|---|---|---|
| OCCT | **8.0.1** | cascade-ios tree, extended to the full `${OCC_LIBRARIES}` set |
| Python | **3.13.18** | BeeWare Python-Apple-support **3.13-b18** prebuilt XCFramework (resolved 2026-10-29, spike S3 A1); asset sha256 `d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d`; PEP 730 upstream build as fallback |
| Coin | **4.0.10** | external build against gl4es (spike S4); the tree also vendors a coin submodule (above) — S4 records any material version difference |
| Boost | **1.88** | pinning `libboost_devel`/`libboost_headers`/`libboost_python_devel` all `1.88`. ⚠️ Research synthesis said 1.90 — live pinning says **1.88**, and the feedstock proves this snapshot against pinning, so 1.88 is the pin. Compiled libs only: program_options, regex, thread, date_time |
| SMESH | **9.9.0.0** (feedstock floor `smesh >=9.9`; not a pinning key) | FreeCAD's bundled copy (`src/3rdParty/salomesmesh`) is primary |
| HDF5 | **1.14.6** | |
| VTK | **9.7.0** | subset only, FEM phases (stage S6). ⚠️ Fem links `${VTK_LIBRARIES}` **unconditionally** (pinned `Mod/Fem/App/CMakeLists.txt:232`, FemGui likewise) and `SetupSalomeSMESH.cmake` forces `BUILD_FEM_VTK ON` when SMESH is on — so M4's VTK-off shape needs an iOS-guarded patch or the subset; decided from the file, recorded in INVENTORY.md |
| Xerces-C | **3.3** (pinning `xerces_c: '3.3'`) | built-in transcoder, no ICU |
| Eigen | ⚠️ DISCREPANCY OPEN | synthesis said 3.4; pinning carries `eigen_abi_devel: '5.0.1'` and no plain `eigen` key. S1 stages 3.4.0 (header-only; FreeCAD's FindEigen3 historically accepts ≥3.3). Settled definitively at the S7 configure — if it demands 5.x, swapping a header-only pin is trivial. Do not treat either number as final until then |
| yaml-cpp | **0.8** | not a pinning key; from the synthesis/feedstock environment |
| FreeType | **2.x** (pinning `freetype: 2`) | our exact staging pin: 2.13.3 |
| pivy | **≥ 0.6.10** (feedstock floor) | vendored submodule also present (above); ships with the GUI from M2 |
| fmt | vendored | `FREECAD_USE_EXTERNAL_FMT=OFF` |
| PCL | OFF | `FREECAD_USE_PCL=OFF` |

## Our toolchain pins

| Item | Value |
|---|---|
| Qt | **6.9.3** (primary; fallback 6.8.3) — dual-kit aqtinstall: mac desktop host tools + `mac ios` target; `FREECAD_QT_VERSION=6` forced. Conda's Qt is 6.11 (`qt6_main: '6.11'`) but the pinned source has **no Qt 6.x minor floor** (`SetupQt.cmake`: `find_package(Qt6 REQUIRED)` unversioned; highest guards are `< 6.9.0` fallbacks; sole 6.10 reference is WIN32-only) — Stage-7 configure remains the deciding experiment |
| PySide / Shiboken | OFF for the shipping configuration (`FREECAD_USE_PYSIDE=OFF`, `FREECAD_USE_SHIBOKEN=OFF`, `FREECAD_CHECK_PYSIDE=OFF`) |
| cascade-ios commit | `7453e03223f3cf2c7683690f6b234f0e0cb77251` (`main` HEAD at freeze — the same commit MetalCAD 1.22 pins; the OCCT extension lands on top) |
| Runner | `macos-26`, standard GitHub-hosted only |
| iOS deployment target | 17.0 |
| Python linking | `BUILD_DYNAMIC_LINK_PYTHON=OFF` |
