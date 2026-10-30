# FreeCAD iPad port — inventory & stage ledger

Facts read from sources and build records, kept current as stages land.
Pins live in `PIN.md`; this file records what exists, what is proven,
and the patch series.

## Stage ladder (status)

| Stage | Contents | Status |
|---|---|---|
| S0 | Toolchain smoke: Qt 6.9.3 dual-kit aqtinstall + Widgets smoke app (FEBio recipe) | **GREEN** (coordinator-verified 2026-10-29): smoke job success on the jobs endpoint across five consecutive recent runs (40963847696, 40965203775, 40965946223, 40966449017, 40967592114); report artifact downloaded from run 40967592114 (551 B) and read: Qt **6.9.3** landed (desktop kit dir `macos`, iOS kit `ios`, discovered dynamically), configure variant A, SDK iPhoneOS26.5, binary Mach-O arm64, `QIOSIntegration` present in strings. (The spine session's original run citations were scrambled by API replica oscillation — the stage's green status was re-verified independently; see the S1 correction note.) |
| S1 | Foundations: zlib → FreeType → HarfBuzz → yaml-cpp → Xerces-C → Eigen → Boost (compiled libs only) | **GREEN** 2026-10-29: run **40967591972** job success; artifact `iosdeps-foundations-7d69d116…tar.zst` **11,959,861 B**, downloaded + unpacked + verified (libz/libfreetype/libharfbuzz/libyaml-cpp/libxerces-c + Boost program_options/thread/date_time `.a`s, Mach-O arm64 objects; Eigen headers). **CORRECTION:** the earlier "GREEN (baseline), run 40920095148, 159,843,510 B" entry was a **false sighting** — API replica oscillation during the spine session; that run actually FAILED at the SDK stage with no artifact, and until 40967591972 every real foundations build had failed (only the skeleton shells ever succeeded). Two latent defects fell in sequence as earlier ones were fixed (SDK discovery → yaml-cpp/CMake 4.x policy → Xerces samples bundle flag → Boost): the archives.boost.io 1.88.0 tarball is the **b2-layout** archive with **no root CMakeLists.txt**, so the superproject route now fetches `boost-1.88.0-cmake.tar.gz` from the boostorg GitHub release (sha256-verified in-script) with a layout guard. **Boost.Regex is an INTERFACE (header-only) target in 1.88's CMake build — no `libboost_regex.a` exists via this route**; FreeCAD links `Boost::regex` as that INTERFACE target. Xerces-C transcoder = **iconv** (gnuiconv probe fails under the toolchain; no ICU) |
| S2 | OCCT extension: census `${OCC_LIBRARIES}` vs cascade-ios 23 toolkits → extend staging to the full set; MetalCAD non-regression | **GREEN** 2026-10-29: cascade-ios extended 23 → **35 toolkits** at HEAD `1efb702005ec026e3c42534dda3eabef2e1bd173` — the 12 census toolkits added (2,148 files, every file sha256-verified against the official OCCT V8_0_1 tarball) + TKService/TKXCAF un-pruning (7 files); host proof compiles all 12 with 0 failures. This is upstream OCCT 8.0.1, the same engine/source MetalCAD runs — only toolkit completeness and build configuration differ. **MetalCAD non-regression PASSED** (coordinator-verified against descendant pin `061875afb5384227db5f39cba81266cf889257a4`: IPA job + kit tests green, artifact 10,787,134 B). **deps-occt GREEN:** run **40983737180**, job success (standard macos-26, ~68 min); artifact `iosdeps-occt-8.0.1-266feda0339664d1d538caeaf9776bc5b4e2f49d1ced52275ae124065436e4e4` **26,217,801 B** (tarball 179 MiB → 25.0 MiB zstd + `occt-report.txt`); in-job verification passed: all 35 `libTK*.a` arm64 + 14 hallmark symbols. Failure ledger: runs 40929074102/40941712162/40943809566/40944917578 died on SDK discovery (root cause: the workflow's own maximize-space step deleted the sibling Xcode bundles holding the platform; fix = deletion removed + script-side `find_sdk()` scan/`-downloadPlatform` fallback + ccache wiring); run 40965749697 compiled all 35 toolkits but the piped `nm \| grep -q` hallmark probe false-negatived on every check (rewritten file-based, + `ranlib` after `ar`); run 40975856297 passed verification but died on a SIGPIPE/pipefail tree listing (guarded with `\|\| true`) |
| S3 | Python spike (BeeWare 3.13 XCFramework + App/Part stack: TestPartApp, STEP round-trip, PartDesign recompute) | **Phase A1 PASS (SIMULATOR)** 2026-10-29: Python 3.13.18 (BeeWare 3.13-b18) embeds, 59/61 stdlib imports OK (tkinter/turtle only), ctypes calls work, device arm64 build OK; verdict `hidden_files/research/s3-spike-verdict.md` in the goal workspace. **Phase A2 PENDING-DEPS** (real foundations/OCCT prefixes not yet landed; probe + gated build staged in `Spike/S3/`) |
| S4 | Graphics spike: gl4es + Coin 4.0.10 + vendored QuarterWidget (Tiers 0–1 first) | gated on S3/S4 report before Stage 7 |
| S5 | Data layer: HDF5 → SMESH (bundled copy) | not started |
| S6 | VTK subset (FEM phases only) | deferred |
| S7 | FreeCAD itself: configure (Qt experiment first) → build | **BLOCKED by the hard gate: S3 + S4 verdicts first** |
| S8 | Bundle + unsigned IPA | not started |

## First Stage-7 build — LEAN SCOPE (plan of record, 2026-10-29 22:17 ET)

Sean's speed-up directive: the FIRST Stage-7 build ships the **lean
Phase-1 workbench set only — Part, PartDesign, Sketcher, Spreadsheet,
Mesh, Import** — the modelling core that gets him sketching and
padding soonest. Everything else (FEM, TechDraw, Assembly, CAM,
Draft/BIM, the VTK post stack) is explicitly deferred to follow-up
builds AFTER the lean build reaches the device; the full workbench
set must not inflate the first cold build or its failure surface.
Consequences already reflected in planning: the S3-A2 console stack
is configured with exactly this module set, so its verdict maps 1:1
to the first build's scope; **no VTK stage is on the first build's
critical path** (the lean set links no VTK — the Fem/SMESH VTK need
belongs to the deferred FEM line); the S5 data stage's VTK subset is
likewise FEM-line work, not a Stage-7 prerequisite. The twin-spike
gate is unchanged by this directive: no Stage-7 build until S3 and
S4 have both reported against their kill criteria.

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

## Qt gate (synthesis §1.3) — Phase-1 verdict: GATE-PASS (2026-10-29)

Full record: goal workspace `hidden_files/research/qt-gate-probe.md`.
Run `40971926782` (job success; evidence artifact `qt-gate-evidence`):
a battery replicating SetupQt.cmake's exact Qt6+GUI REQUIRED component
list **configured, compiled, and LINKED** against the Qt 6.9.3 iOS kit
(arm64, deployment 17.0), exercising the snapshot's newest-branch APIs
(`QImage::flip/flipped` at the three `< 6.9.0` fallback sites,
`QPagedPaintDevice::PdfVersion_X4`, `QCheckBox::checkStateChanged`,
QOpenGLWidget, QUiLoader, QSvg, QPrinter, QtConcurrent…). Host scan
agrees: `QT_VERSION_CHECK` minors present are 0–9 only; references to
Qt ≥ 6.10: **zero**. **Zero [QT-API] failures in six probe runs** — Qt
6.9.3 stands as the primary kit; no §1.3 fallback is needed. Phase 2
(full configure depth) runs when OCCT + ICU artifacts exist.

Two findings ride into Stage 7's configure, recorded here so they
can't be lost:
- **ICU is a hard dependency with no shortcut — now BUILT.** FreeCAD's
  top-level `CMakeLists.txt:98` requires ICU (uc/i18n); FindICU in
  cross mode cannot be satisfied by the SDK's `libicucore` (seven
  seeding layouts proven insufficient by the probe). This settles
  synthesis appendix item 4: the Xerces built-in-transcoder route does
  NOT cover FreeCADBase's own ICU requirement. **Resolution
  (2026-10-29):** the foundations line now builds **icu4c 78.1**
  (sha256-pinned; host build for tools, then `--host=arm-apple-darwin`
  static target build) with the **full data library**
  (`libicudata.a` 33 MB — stubdata rejected: an external `.dat` is
  unreliable in an iOS bundle). Green run `40985309078`, artifact
  `iosdeps-foundations-06c242f5…` (23,533,405 B, download-verified,
  zero `.dylib`s in prefix). The stage's own probe prints
  `FINDICU-OK` (found 78.1, uc+i18n, linked `u_strlen`/`u_errorName`).
  **Stage-7 configure note (from the probe's hardest failure):** seed
  `ICU_INCLUDE_DIR` (and root) to the prefix — otherwise FindICU mixes
  SDK libicucore headers (renaming OFF) with our renamed libraries
  and the link fails on undefined `_u_*` symbols.
- **rcc compression flags:** the official Qt 6.9.3 host `rcc` has no
  compiled-in zstd and rejects FreeCAD's default `--compress 19`
  under zlib. Stage 7 configures with
  `FREECAD_RCC_COMPRESSION_ALGO=zlib` +
  `FREECAD_RCC_COMPRESSION_LEVEL=9`. [CONFIG], not a Qt gap.
- **Maximize-space landmine:** the deps workflows' sibling-Xcode
  deletion destroyed the iPhoneOS SDK mid-flight on some runners
  (killed probe run 40957050742 and OCCT run 40929074102 — the "sick
  runner" explanation was incomplete). Deletion loops removed from
  deps-foundations/data/python/vtk (coordinator) and deps-occt
  (owner-directed); SDK discovery belongs to the build scripts.

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
| deps-occt | run 40983737180, success (2026-10-29) | ~68 min (run 01:05:36Z→02:13:14Z; job 66 min) | artifact `iosdeps-occt-8.0.1-266feda0339664d1d538caeaf9776bc5b4e2f49d1ced52275ae124065436e4e4`, 26,217,801 B (contains the `.tar.zst`, 25.0 MiB, + `occt-report.txt`; contents verified in-job: 35 arm64 `libTK*.a` + 14 hallmark symbols) |
| deps-data | — | — | — |
| deps-vtk | — | — | — |
| deps-python | run 40916785036, success (2026-10-29) | — | `iosdeps-python-c779deaaae9e8557c3e59f5314b9bfcc45b7bfbe37c7df0ffd4e790f164b3506.tar.zst` (46,153,608 B artifact, contents verified) |
| spike-s3 | runs 40916784992 + 40917033234, both success (2026-10-29) | — | `spike-s3-results` (simulator probe report + device-build report) |
| build-freecad | smoke job green in runs 40919232480 + 40924270539 (2026-10-29); core/workbench jobs are still shells (marker artifacts only) | smoke job 4m23s (run 40919232480) | `stage0-smoke-report` (report.txt: Qt 6.9.3, arm64, QIOSIntegration) |
