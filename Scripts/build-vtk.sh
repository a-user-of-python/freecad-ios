#!/bin/bash
# S6 — VTK subset (shell only; DEFERRED to the FEM phases).
#
# Real stage: host VTK compile-tools build -> target build of ONLY the
# modules named by the pinned snapshot's actual find_package(VTK
# COMPONENTS ...) calls. First act of the real stage: read the pinned
# Mod/Fem/App/CMakeLists.txt and settle whether the App-level VTK link
# is unconditional (research discrepancy, synthesis appendix 1).
# Output: dist/iosdeps-vtk-$DEPS_HASH.tar.zst containing ios-prefix/.
set -euo pipefail
echo "=============================================================="
echo " STAGE S6 (VTK subset): SHELL ONLY — deferred to FEM phases"
echo "=============================================================="
mkdir -p dist
{
  echo "S6 VTK subset is a workflow shell; deferred to the FEM phases."
  echo "Would produce: iosdeps-vtk-${DEPS_HASH:-UNSET}.tar.zst"
} > dist/STAGE-NOT-IMPLEMENTED.txt
