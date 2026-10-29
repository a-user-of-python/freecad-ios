# Patches

Patches against the pinned FreeCAD snapshot (see `../PIN.md`) live
here, applied in filename order by the build scripts.

Rules (the FEBio discipline):

- Numbered: `NNNN-short-name.patch`, applied in order, idempotent
  (re-running the apply step on a patched tree is a no-op or a clean
  failure, never a half-state).
- iOS-guarded: every source change is wrapped so desktop builds of the
  same tree are unaffected (`#ifdef Q_OS_IOS`, CMake platform checks,
  or configure options).
- Enumerated in `../INVENTORY.md` with the reason for each patch
  before it lands.
- Shell/platform layer only. No geometry-engine changes; OCCT sources
  are never modified at all (LGPL rule).
