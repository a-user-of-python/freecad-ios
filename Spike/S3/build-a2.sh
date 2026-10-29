#!/bin/bash
# Spike S3 Phase A2 — FreeCAD console stack on the embedded interpreter.
#
# STAGED, GATED ON DEPS. This script refuses to run until both A2
# dependency tarballs exist in ./ios-deps-artifacts/ (downloaded by
# spike-s3-a2.yml from the deps-foundations / deps-occt runs):
#   iosdeps-foundations-<hash>.tar.zst   (S1: Boost, Xerces-C, Eigen…)
#   iosdeps-occt-8.0.1-<hash>.tar.zst    (S2: full ${OCC_LIBRARIES} set)
# plus the Python prefix from deps-python (Scripts/build-python.sh).
# That gate is deliberate: A2 is meaningless against a partial stack.
#
# Plan when the gate opens (synthesis §1.4/§3, front 03 Phase A):
#   1. Extract the pinned weekly tarball (PIN.md URL + sha256).
#   2. Configure the CONSOLE stack only, iOS arm64 simulator slice
#      first (device staging is a later step):
#        BUILD_GUI=OFF, FREECAD_USE_PYSIDE=OFF,
#        FREECAD_USE_SHIBOKEN=OFF, FREECAD_CHECK_PYSIDE=OFF,
#        BUILD_DYNAMIC_LINK_PYTHON=OFF, FREECAD_USE_PCL=OFF,
#        modules limited to Base/App + Part, PartDesign, Sketcher,
#        Import, Mesh, Spreadsheet, Test (BUILD_* per-module OFF for
#        the rest), Python3 pointed at the BeeWare prefix,
#        OpenCascade at the S2 prefix, Boost/Xerces at S1 prefix.
#   3. Build (modular libs), collect the install tree.
#   4. Package PACKAGING MODEL 1 (front 03 §1): the Mod/ tree and its
#      C++ extension .so modules copied into the harness app bundle,
#      signed in-bundle, loaded by the normal import system (dlopen).
#      ESCALATION (pre-planned, synthesis §3): if model 1 fails,
#      switch the affected modules to MODEL 3 — static archives
#      linked into the harness binary, pre-registered with
#      PyImport_AppendInittab — BEFORE declaring any failure.
#   5. Run probe_a2.py through the embedded interpreter on the
#      SIMULATOR (labelled as such) and compare its VOLUME lines
#      against the desktop reference from the same script.
set -euo pipefail
cd "$(dirname "$0")/../.."

missing=0
for pat in "iosdeps-foundations-*.tar.zst" "iosdeps-occt-*.tar.zst" \
           "iosdeps-python-*.tar.zst"; do
  if ! ls ios-deps-artifacts/$pat >/dev/null 2>&1; then
    echo "A2 PENDING DEPS: ios-deps-artifacts/$pat not present"
    missing=1
  fi
done
if [ "$missing" = 1 ]; then
  echo "A2-GATE-CLOSED (deps not landed; nothing built, nothing failed)"
  exit 0
fi

echo "A2-GATE-OPEN: all dependency tarballs present."
echo "TODO(A2 execution): configure/build/package/run per the plan in"
echo "this script's header. This branch is reached only with deps in"
echo "hand; implement it in the A2 execution pass, not before."
exit 1
