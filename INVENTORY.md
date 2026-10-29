# FreeCAD iPad port — inventory & stage ledger

Facts read from sources and build records, kept current as stages land.
Pins live in `PIN.md`; this file records what exists, what is proven,
and the patch series.

## Stage ladder (status)

| Stage | Contents | Status |
|---|---|---|
| S0 | Toolchain smoke: Qt 6.9.3 dual-kit aqtinstall + Widgets smoke app (FEBio recipe) | **GREEN** (coordinator-verified 2026-10-29): smoke job success on the jobs endpoint across five consecutive recent runs (40963847696, 40965203775, 40965946223, 40966449017, 40967592114); report artifact downloaded from run 40967592114 (551 B) and read: Qt **6.9.3** landed (desktop kit dir `macos`, iOS kit `ios`, discovered dynamically), configure variant A, SDK iPhoneOS26.5, binary Mach-O arm64, `QIOSIntegration` present in strings. (The spine session's original run citations were scrambled by API replica oscillation — the stage's green status was re-verified independently; see the S1 correction note.) |
| S1 | Foundations: zlib → FreeType → HarfBuzz → yaml-cpp → Xerces-C → Eigen → Boost (compiled libs only) | **GREEN** 2026-10-29: run **40967591972** job success; artifact `iosdeps-foundations-7d69d116…tar.zst` **11,959,861 B**, downloaded + unpacked + verified (libz/libfreetype/libharfbuzz/libyaml-cpp/libxerces-c + Boost program_options/thread/date_time `.a`s, Mach-O arm64 objects; Eigen headers). **CORRECTION:** the earlier "GREEN (baseline), run 40920095148, 159,843,510 B" entry was a **false sighting** — API replica oscillation during the spine session; that run actually FAILED at the SDK stage with no artifact, and until 40967591972 every real foundations build had failed (only the skeleton shells ever succeeded). Two latent defects fell in sequence as earlier ones were fixed (SDK discovery → yaml-cpp/CMake 4.x policy → Xerces samples bundle flag → Boost): the archives.boost.io 1.88.0 tarball is the **b2-layout** archive with **no root CMakeLists.txt**, so the superproject route now fetches `boost-1.88.0-cmake.tar.gz` from the boostorg GitHub release (sha256-verified in-script) with a layout guard. **Boost.Regex is an INTERFACE (header-only) target in 1.88's CMake build — no `libboost_regex.a` exists via this route**; FreeCAD links `Boost::regex` as that INTERFACE target. Xerces-C transcoder = **iconv** (gnuiconv probe fails under the toolchain; no ICU) |
| S2 | OCCT extension: census `${OCC_LIBRARIES}` vs cascade-ios 23 toolkits → extend staging to the full set; MetalCAD non-regression | **census DONE (configured, triple-verified)** — work order = 12 toolkits: TKHLR, TKFeat, TKExpress, TKDEIGES, TKDEGLTF, TKDESTL, TKBin, TKBinL, TKVCAF, TKMeshVS, TKV3d, TKRWMesh → target tree 35. TKXml/TKDEVRML are NOT required (front 01/synthesis expectation corrected by the census). Extension in progress |
| S3 | Python spike (BeeWare 3.13 XCFramework + App/Part stack: TestPartApp, STEP round-trip, PartDesign recompute) | **Phase A1 PASS (SIMULATOR)** 2026-10-29: Python 3.13.18 (BeeWare 3.13-b18) embeds, 59/61 stdlib imports OK (tkinter/turtle only), ctypes calls work, device arm64 build OK; verdict `hidden_files/research/s3-spike-verdict.md` in the goal workspace. **Phase A2 PENDING-DEPS** (real foundations/OCCT prefixes not yet landed; probe + gated build staged in `Spike/S3/`) |
| S4 | Graphics spike: gl4es + Coin 4.0.10 + vendored QuarterWidget (Tiers 0–1 first) | gated on S3/S4 report before Stage 7 |
| S5 | Data layer: HDF5 → SMESH (bundled copy) | not started |
| S6 | VTK subset (FEM phases only) | deferred |
| S7 | FreeCAD itself: configure (Qt experiment first) → build | **BLOCKED by the hard gate: S3 + S4 verdicts first** |
| S8 | Bundle + unsigned IPA | not started |

## Resolved research discrepancies

- **Fem VTK gating (synthesis appendix 1) — RESOLVED 2026-10-29 from
  the pinned source:** front 04 was right. `Mod/Fem/App/CMakeLists.txt`
  links `${VTK_LIBRARIES}` unconditionally (line 232; FemGui the same;
  include dirs unconditional at line 228). Only FemPost/FemVTK
  *sources* are gated by `BUILD_FEM_VTK`, and there is no OFF path:
  `SetupSalomeSMESH.cmake` runs `find_package(VTK REQUIRED)` whenever
  SMESH is on and sets `BUILD_FEM_VTK ON`. Consequence: the M4
  VTK-off shape requires an iOS-guarded patch (or the S6 subset
  arriving earlier). S6's "first hour" task is therefore already done.
- **Boost version:** synthesis said 1.90; live pinning says 1.88.
  PIN.md pins 1.88 (the feedstock-proven pairing).
- **Eigen version:** open (3.4 staged vs pinning's 5.0.1 ABI line) —
  settled at the S7 configure; see PIN.md.

## CI decisions (Front 6 audit dispositions, 2026-10-29)

Full audit: goal workspace `hidden_files/research/ci-readiness.md`.
- **Fixed by the audit** (commit `71854939`): D1 ccache key collision/
  frozen cache, D2 masked core-artifact download, D5 xcode-select
  reset after sibling-Xcode deletion, D7 smoke timeout (60 min).
- **Fixed by the coordinator** (surgical commits, tree-verified):
  **D8** — every workflow now has a `concurrency:` group
  (`<workflow>-<ref>`, `cancel-in-progress: false`): one running + one
  pending per workflow; re-dispatches replace the pending run instead
  of stacking duplicates. **D9** — `deps-foundations` hash + trigger
  paths now include `Scripts/qt-install.inc.sh`. **D4** —
  `build-freecad.yml` takes optional `workflow_dispatch` run-id inputs
  (foundations/occt/python/data) and downloads each dep tarball from
  that run (the old pattern-only download could only ever see the
  current run's artifacts, i.e. none), with a one-tarball-per-family
  assertion against cross-generation mixing. **D6** — the shell IPA
  artifact is renamed `FreeCAD-unsigned-SHELL`; **whoever lands the
  real Stage-7 `build-freecad.sh` flips it back to
  `FreeCAD-unsigned` in the same change.**
- **Reported, owned elsewhere:** D3 — ccache is cached but never wired
  to a compiler (`CMAKE_*_COMPILER_LAUNCHER` absent); until the
  Stage-7 script body lands it, every build-freecad run is effectively
  cold. Deps ccache recommended for foundations + OCCT when their
  scripts next change (spine/OCCT owners).

## Patch series

None yet. Every future patch: numbered (`NNNN-short-name.patch`),
idempotent, iOS-guarded (`#ifdef Q_OS_IOS` / CMake platform checks),
enumerated here with its reason before the series grows — the FEBio
discipline.

## CI baseline timings

Recorded from the first successful run of each workflow; every later
run is judged against these. (Cold FreeCAD build estimate from
research: 180–330 min vs the 360-min standard-runner cap; ccache +
the pre-built two-job split in `build-freecad.yml` are the standing
mitigations.)

| Workflow | First green run | Duration | Artifact |
|---|---|---|---|
| deps-foundations | run 40967591972, success (2026-10-29) — **corrects the false 40920095148 sighting, see the S1 row** | — | `iosdeps-foundations-7d69d116a913cb78697aa4db756a786c520bbe826f748bd9534691c1509c405b.tar.zst`, 11,959,861 B (download-verified) |
| deps-occt | — | — | — |
| deps-data | — | — | — |
| deps-vtk | — | — | — |
| deps-python | run 40916785036, success (2026-10-29) | — | `iosdeps-python-c779deaaae9e8557c3e59f5314b9bfcc45b7bfbe37c7df0ffd4e790f164b3506.tar.zst` (46,153,608 B artifact, contents verified) |
| spike-s3 | runs 40916784992 + 40917033234, both success (2026-10-29) | — | `spike-s3-results` (simulator probe report + device-build report) |
| build-freecad | smoke job green in runs 40919232480 + 40924270539 (2026-10-29); core/workbench jobs are still shells (marker artifacts only) | smoke job 4m23s (run 40919232480) | `stage0-smoke-report` (report.txt: Qt 6.9.3, arm64, QIOSIntegration) |
