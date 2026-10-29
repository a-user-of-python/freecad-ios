# FreeCAD for iPad (iOS port)

The real **FreeCAD** — the same upstream program people run on desktop —
cross-compiled for iPad (iOS arm64), following the same porting pattern
already proven with FEBio Studio on this exact device class: unmodified
upstream source, adjusted only at the platform shell through an
enumerated, iOS-guarded patch series (`Patches/` + `INVENTORY.md`).

- **Target:** a pinned weekly/dev snapshot of FreeCAD `main` — see
  `PIN.md` for the exact frozen snapshot, dependency versions, and
  toolchain pins. Nothing floats; every build consumes only the
  recorded tarballs and commits.
- **Geometry engine:** Open CASCADE Technology **8.0.1**, from the
  cascade-ios tree (extended to FreeCAD's full toolkit set). OCCT is
  licensed under LGPL 2.1 with the Open CASCADE exception; its licence
  texts ship with that tree (`OCCT/LICENSE_LGPL_21.txt`,
  `OCCT/OCCT_LGPL_EXCEPTION.txt`) and OCCT sources are never modified.
- **Build:** GitHub Actions, public repo, standard `macos-26` runners
  only. Dependencies build once into content-hash-named tarball
  artifacts (`deps-*.yml` workflows); the app workflow
  (`build-freecad.yml`) consumes them and produces an unsigned IPA.
- **Status:** see `INVENTORY.md` for the stage ladder and what is
  proven so far. Green CI is evidence, never the verdict — the device
  is.
