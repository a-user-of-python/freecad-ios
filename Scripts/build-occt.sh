#!/bin/bash
# S2 — OCCT extension (shell only).
#
# Real stage (Action 2): clone cascade-ios at the PIN.md commit (its
# staging extended additively from the 23-toolkit MetalCAD subset to
# the full ${OCC_LIBRARIES} set from the census), build the static
# libraries for iOS arm64 with cascade's unchanged per-toolkit
# FILES.cmake enumeration + static-lib assembly, verify with the
# cascade facade harness, and package dist/iosdeps-occt-8.0.1-$DEPS_HASH.tar.zst.
# MetalCAD non-regression against the extended tree is checked in the
# metalcad pipeline before FreeCAD consumes this artifact.
set -euo pipefail
echo "=============================================================="
echo " STAGE S2 (OCCT extension): SHELL ONLY — not yet implemented"
echo "=============================================================="
mkdir -p dist
{
  echo "S2 OCCT extension is a workflow shell; the real stage lands in Action 2."
  echo "Would produce: iosdeps-occt-8.0.1-${DEPS_HASH:-UNSET}.tar.zst"
} > dist/STAGE-NOT-IMPLEMENTED.txt
