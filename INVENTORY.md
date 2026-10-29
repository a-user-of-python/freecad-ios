# FreeCAD iPad port — inventory & stage ledger

Facts read from sources and build records, kept current as stages land.
Pins live in `PIN.md`; this file records what exists, what is proven,
and the patch series.

## Stage ladder (status)

| Stage | Contents | Status |
|---|---|---|
| S0 | Toolchain smoke: Qt 6.9.3 dual-kit aqtinstall + Widgets smoke app (FEBio recipe) | not started |
| S1 | Foundations: zlib → FreeType → HarfBuzz → yaml-cpp → Xerces-C → Eigen → Boost (compiled libs only) | not started |
| S2 | OCCT extension: census `${OCC_LIBRARIES}` vs cascade-ios 23 toolkits → extend staging to the full set; MetalCAD non-regression | census in progress |
| S3 | Python spike (BeeWare 3.13 XCFramework + App/Part stack: TestPartApp, STEP round-trip, PartDesign recompute) | gated on S3/S4 report before Stage 7 |
| S4 | Graphics spike: gl4es + Coin 4.0.10 + vendored QuarterWidget (Tiers 0–1 first) | gated on S3/S4 report before Stage 7 |
| S5 | Data layer: HDF5 → SMESH (bundled copy) | not started |
| S6 | VTK subset (FEM phases only) | deferred |
| S7 | FreeCAD itself: configure (Qt experiment first) → build | **BLOCKED by the hard gate: S3 + S4 verdicts first** |
| S8 | Bundle + unsigned IPA | not started |

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
| deps-foundations | — | — | — |
| deps-occt | — | — | — |
| deps-data | — | — | — |
| deps-vtk | — | — | — |
| deps-python | — | — | — |
| build-freecad | — | — | — |
