#!/bin/bash
# S5 — Data layer (shell only).
#
# Real stage: HDF5 (host tools first, target build with pre-seeded
# try-run results) -> SMESH 9.9.0.0 from FreeCAD's bundled copy
# (src/3rdParty/salomesmesh; the conda-external smesh build is the
# fallback). MEFISTO2's single Fortran file (trte.f) takes the f2c
# translation route by default. Output:
# dist/iosdeps-data-$DEPS_HASH.tar.zst containing ios-prefix/.
set -euo pipefail
echo "=============================================================="
echo " STAGE S5 (data layer): SHELL ONLY — not yet implemented"
echo "=============================================================="
mkdir -p dist
{
  echo "S5 data layer is a workflow shell."
  echo "Would produce: iosdeps-data-${DEPS_HASH:-UNSET}.tar.zst"
} > dist/STAGE-NOT-IMPLEMENTED.txt
