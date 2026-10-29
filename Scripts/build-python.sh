#!/bin/bash
# S3 chain — Python for iOS (shell only).
#
# Real stage (Action 3, spike S3): Python 3.13 via the BeeWare
# XCFramework route (PEP 730 upstream build as fallback/audit),
# packaged with the FreeCAD extension-module strategy the spike
# settles (in-bundle dlopen first; static AppendInittab registration
# as the pre-planned escalation). Output:
# dist/iosdeps-python-$DEPS_HASH.tar.zst containing ios-prefix/ and
# the Python XCFramework.
set -euo pipefail
echo "=============================================================="
echo " STAGE S3-chain (Python): SHELL ONLY — not yet implemented"
echo "=============================================================="
mkdir -p dist
{
  echo "deps-python is a workflow shell; the real stage lands with spike S3 (Action 3)."
  echo "Would produce: iosdeps-python-${DEPS_HASH:-UNSET}.tar.zst"
} > dist/STAGE-NOT-IMPLEMENTED.txt
