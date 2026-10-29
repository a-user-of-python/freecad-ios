# Spike S3 — Python (Phase A1 harness)

Minimal embedding proof for the port's Python layer (synthesis §3/S3,
research front 03 Phase A). Not FreeCAD code.

- `main.m` — ObjC iOS app: links `Python.xcframework`, initialises the
  interpreter with its home at the in-bundle `python/` tree, runs
  `probe.py`, leaves the report in `Documents/s3-result.txt`.
- `probe.py` — imports a stdlib census (incl. `ctypes`, `ssl`) inside
  the embedded interpreter and records OK/FAIL per module. A failed
  import is packaging data, not a spike failure.
- `convert_dynload.py` — BeeWare's official packaging route: every
  `lib-dynload/*.so` becomes a signed `.framework` plus a `.fwork`
  pointer (CPython's AppleFrameworkLoader).
- `build-and-run.sh` — downloads the pinned BeeWare asset (same pin as
  `Scripts/build-python.sh`), builds simulator + device arm64,
  assembles/signs both `.app`s by hand, runs the simulator build via
  `simctl`, and retrieves the result file.
- `Info.plist` — the harness app's plist (bundle id
  `org.freecad.s3spike`).

Run by `.github/workflows/spike-s3.yml` on `macos-26`. All runtime
evidence from this harness is **SIMULATOR** evidence; the device build
is compile/link/package proof only.
