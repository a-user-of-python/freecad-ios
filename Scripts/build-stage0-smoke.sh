#!/bin/bash
# S0 — Toolchain smoke (shell only).
#
# Real stage (Action 2): FEBio's Stage-0 recipe, adapted — aqtinstall
# Qt 6.9.3 dual kit (mac desktop clang_64 host tools + mac ios target),
# then a minimal Widgets app configured with qt.toolchain.cmake +
# QT_HOST_PATH and built for iOS arm64, with the FEBio verify step
# (arm64 + QIOSIntegration strings) before upload. Fallback 6.8.3 if
# the 6.9.3 kit layout drifts.
set -euo pipefail
echo "=============================================================="
echo " STAGE S0 (toolchain smoke): SHELL ONLY — not yet implemented"
echo "=============================================================="
mkdir -p dist-smoke
echo "S0 toolchain smoke is a workflow shell; the real stage lands in Action 2." \
  > dist-smoke/STAGE-NOT-IMPLEMENTED.txt
